// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../../Strategy.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {IComet} from "../../../interfaces/compound/IComet.sol";
import {IRewards} from "../../../interfaces/compound/IRewards.sol";

/// @title This strategy will deposit base asset i.e. USDC in Compound V3 and earn interest.
contract CompoundV3 is Strategy {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:vesper.storage.Strategy.CompoundV3
    struct CompoundV3Storage {
        IComet _comet;
        IRewards _compRewards;
        address _rewardToken;
    }

    bytes32 private constant CompoundV3StorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.CompoundV3")) - 1)) & ~bytes32(uint256(0xff));

    function _getCompoundV3Storage() internal pure returns (CompoundV3Storage storage $) {
        bytes32 _location = CompoundV3StorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        address compRewards_,
        address rewardToken_,
        address comet_,
        string memory name_
    ) external initializer {
        __Strategy_init(pool_, swapper_, comet_, name_);
        if (compRewards_ == address(0) || rewardToken_ == address(0)) revert AddressIsNull();
        CompoundV3Storage storage $ = _getCompoundV3Storage();
        $._comet = IComet(comet_);
        $._compRewards = IRewards(compRewards_);
        $._rewardToken = rewardToken_;
    }

    function comet() public view returns (IComet) {
        return IComet(receiptToken());
    }

    function compRewards() public view returns (IRewards) {
        return _getCompoundV3Storage()._compRewards;
    }

    function rewardToken() public view returns (address) {
        return _getCompoundV3Storage()._rewardToken;
    }

    function tvl() external view override returns (uint256) {
        return comet().balanceOf(address(this)) + collateralToken().balanceOf(address(this));
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        collateralToken().forceApprove(address(comet()), amount_);
        IERC20(rewardToken()).forceApprove(address(swapper()), amount_);
    }

    /// @dev Claim COMP
    function _claimRewards() internal override returns (address, uint256) {
        CompoundV3Storage memory s = _getCompoundV3Storage();
        address _rewardToken = address(s._rewardToken);

        s._compRewards.claim(address(s._comet), address(this), true);
        return (_rewardToken, IERC20(_rewardToken).balanceOf(address(this)));
    }

    /**
     * @dev Deposit collateral in Compound.
     */
    function _deposit(uint256 amount_) internal {
        if (amount_ > 0) {
            comet().supply(address(collateralToken()), amount_);
        }
    }

    function _getAvailableLiquidity() internal view returns (uint256) {
        IComet _comet = comet();
        uint256 _totalSupply = _comet.totalSupply();
        uint256 _totalBorrow = _comet.totalBorrow();
        return _totalSupply > _totalBorrow ? _totalSupply - _totalBorrow : 0;
    }

    /**
     * @dev Generate report for pools accounting and also send profit and any payback to pool.
     */
    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _collateralHere + comet().balanceOf(address(this));
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
        IVesperPool(_pool).reportEarning(_profit, _loss, _payback);
        // After reportEarning strategy may get more collateral from pool. Deposit those in Compound.
        _deposit(_collateralToken.balanceOf(address(this)));
    }

    /// @dev Withdraw collateral here. Do not transfer to pool
    function _withdrawHere(uint256 amount_) internal override {
        IComet _comet = comet();
        // Get minimum of _amount and _available collateral and _availableLiquidity
        uint256 _withdrawAmount = Math.min(
            amount_,
            Math.min(_comet.balanceOf(address(this)), _getAvailableLiquidity())
        );
        _comet.withdraw(address(collateralToken()), _withdrawAmount);
    }
}
