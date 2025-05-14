// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../Strategy.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {IYToken} from "../../interfaces/yearn/IYToken.sol";
import {IStakingRewards} from "../../interfaces/yearn/IStakingRewards.sol";

/// @title This strategy will deposit collateral token in a Yearn vault and stake receipt tokens
/// into staking contract to earn rewards and yield.
contract YearnStaking is Strategy {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:vesper.storage.Strategy.YearnStaking
    struct YearnStakingStorage {
        IStakingRewards _stakingRewards;
        IYToken _yTokenReward;
        uint256 _yTokenDecimals;
    }

    bytes32 private constant YearnStakingStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.YearnStaking")) - 1)) & ~bytes32(uint256(0xff));

    function _getYearnStakingStorage() internal pure returns (YearnStakingStorage storage $) {
        bytes32 _location = YearnStakingStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        IStakingRewards stakingRewards_,
        string memory name_
    ) external initializer {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);

        if (address(stakingRewards_) == address(0)) revert AddressIsNull();

        YearnStakingStorage storage $ = _getYearnStakingStorage();
        $._yTokenDecimals = 10 ** IYToken(receiptToken_).decimals();
        $._stakingRewards = stakingRewards_;
        $._yTokenReward = IYToken(stakingRewards_.rewardsToken());
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return token_ == receiptToken();
    }

    function stakingRewards() public view returns (IStakingRewards) {
        return _getYearnStakingStorage()._stakingRewards;
    }

    function tvl() external view override returns (uint256) {
        return _getCollateralFromYearn() + collateralToken().balanceOf(address(this));
    }

    function yToken() public view returns (IYToken) {
        return IYToken(receiptToken());
    }

    function yTokenDecimals() internal view returns (uint256) {
        return _getYearnStakingStorage()._yTokenDecimals;
    }

    function yTokenReward() public view returns (IYToken) {
        return _getYearnStakingStorage()._yTokenReward;
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        address _yToken = address(yToken());
        collateralToken().forceApprove(_yToken, amount_);
        IERC20(_yToken).forceApprove(address(stakingRewards()), amount_);
    }

    function _claimRewards() internal override {
        // Claim reward and it will give us yToken as reward
        stakingRewards().getReward();
        IYToken _yTokenReward = yTokenReward();
        uint256 _yRewardsAmount = _yTokenReward.balanceOf(address(this));
        if (_yRewardsAmount > 0) {
            // Withdraw actual reward token from yToken
            _yTokenReward.withdraw(_yRewardsAmount);
        }
    }

    function _convertToShares(uint256 collateralAmount_) internal view returns (uint256) {
        return (collateralAmount_ * yTokenDecimals()) / yToken().pricePerShare();
    }

    function _getCollateralFromYearn() internal view returns (uint256) {
        return (_getTotalShares() * yToken().pricePerShare()) / yTokenDecimals();
    }

    function _getTotalShares() internal view returns (uint256) {
        return yToken().balanceOf(address(this)) + stakingRewards().balanceOf(address(this));
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _getCollateralFromYearn() + _collateralHere;

        if (_totalCollateral > _totalDebt) {
            _profit = _totalCollateral - _totalDebt;
        } else {
            _loss = _totalDebt - _totalCollateral;
        }
        uint256 _profitAndExcessDebt = _profit + _excessDebt;
        if (_profitAndExcessDebt > _collateralHere) {
            _withdrawHere(_profitAndExcessDebt - _collateralHere);
            _collateralHere = _collateralToken.balanceOf(address(this));
        }

        // Make sure _collateralHere >= _payback + profit. set actual payback first and then profit
        _payback = Math.min(_collateralHere, _excessDebt);
        _profit = _collateralHere > _payback ? Math.min((_collateralHere - _payback), _profit) : 0;
        _pool.reportEarning(_profit, _loss, _payback);

        // strategy may get new fund. deposit to generate yield
        _collateralHere = _collateralToken.balanceOf(address(this));
        IYToken _yToken = yToken();
        if (_convertToShares(_collateralHere) > 0) {
            _yToken.deposit(_collateralHere);
        }

        // Staking all yTokens to earn rewards
        uint256 _sharesHere = _yToken.balanceOf(address(this));
        if (_sharesHere > 0) {
            stakingRewards().stake(_sharesHere);
        }
    }

    function _withdrawHere(uint256 amount_) internal override {
        // Check staked shares and shares here
        IYToken _yToken = yToken();
        uint256 _sharesRequired = _convertToShares(amount_);
        uint256 _sharesHere = _yToken.balanceOf(address(this));
        if (_sharesRequired > _sharesHere) {
            // Unstake minimum of staked and required
            IStakingRewards _stakingRewards = stakingRewards();
            uint256 _toUnstake = Math.min(_stakingRewards.balanceOf(address(this)), (_sharesRequired - _sharesHere));
            if (_toUnstake > 0) {
                _stakingRewards.withdraw(_toUnstake);
            }
        }

        // Withdraw all available yTokens. Reread balance as unstake will increase balance.
        _sharesHere = _yToken.balanceOf(address(this));
        if (_sharesHere > 0) {
            _yToken.withdraw(_yToken.balanceOf(address(this)));
        }
    }
}
