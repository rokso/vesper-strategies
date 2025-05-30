// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../../Strategy.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {IStargatePoolV2 as IStargatePool} from "../../../interfaces/stargate/v2/IStargatePoolV2.sol";
import {IStargateStaking} from "../../../interfaces/stargate/v2/IStargateStaking.sol";

/// @title This Strategy will deposit collateral token in a StargateV2 Pool to yearn yield.
/// Stake LP token to accrue rewards.
contract StargateV2 is Strategy {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:vesper.storage.Strategy.StargateV2
    struct StargateV2Storage {
        IStargatePool _stargatePool;
        IStargateStaking _stargateStaking;
        address[] _rewardTokens;
    }

    bytes32 private constant StargateV2StorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.StargateV2")) - 1)) & ~bytes32(uint256(0xff));

    function _getStargateV2Storage() internal pure returns (StargateV2Storage storage $) {
        bytes32 _location = StargateV2StorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        IStargatePool stargatePool_,
        IStargateStaking stargateStaking_,
        string memory name_
    ) public initializer {
        if (address(stargatePool_) == address(0)) revert AddressIsNull();
        if (address(stargateStaking_) == address(0)) revert AddressIsNull();

        address _stargateLp = stargatePool_.lpToken();

        __Strategy_init(pool_, swapper_, _stargateLp, name_);

        StargateV2Storage storage $ = _getStargateV2Storage();

        $._stargatePool = stargatePool_;
        $._stargateStaking = stargateStaking_;
        $._rewardTokens = stargateStaking_.rewarder(IERC20(_stargateLp)).rewardTokens();
    }

    function lpAmountStaked() public view returns (uint256 _lpAmountStaked) {
        _lpAmountStaked = stargateStaking().balanceOf(stargateLp(), address(this));
    }

    function rewardTokens() public view returns (address[] memory) {
        return _getStargateV2Storage()._rewardTokens;
    }

    function stargateLp() public view returns (IERC20) {
        return IERC20(receiptToken());
    }

    function stargatePool() public view returns (IStargatePool) {
        return _getStargateV2Storage()._stargatePool;
    }

    function stargateStaking() public view returns (IStargateStaking) {
        return _getStargateV2Storage()._stargateStaking;
    }

    function tvl() external view override returns (uint256) {
        return _getCollateralInStargate() + collateralToken().balanceOf(address(this));
    }

    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);

        StargateV2Storage memory s = _getStargateV2Storage();
        collateralToken().forceApprove(address(s._stargatePool), amount_);
        stargateLp().forceApprove(address(s._stargateStaking), amount_);

        address _swapper = address(swapper());
        address[] memory _rewardTokens = s._rewardTokens;
        uint256 _len = _rewardTokens.length;
        for (uint256 i; i < _len; ++i) {
            IERC20(_rewardTokens[i]).forceApprove(_swapper, amount_);
        }
    }

    function _claimAndSwapRewards() internal virtual override {
        IERC20[] memory _lpTokens = new IERC20[](1);
        _lpTokens[0] = stargateLp();
        stargateStaking().claim(_lpTokens);

        address _collateralToken = address(collateralToken());
        address[] memory _rewardTokens = rewardTokens();
        uint256 _len = _rewardTokens.length;
        for (uint256 i; i < _len; ++i) {
            uint256 _rewardsAmount = IERC20(_rewardTokens[i]).balanceOf(address(this));
            if (_rewardsAmount > 0 && _rewardTokens[i] != _collateralToken) {
                _trySwapExactInput(_rewardTokens[i], _collateralToken, _rewardsAmount);
            }
        }
    }

    function _deposit(uint256 collateralAmount_) internal virtual {
        if (collateralAmount_ > 0) {
            stargatePool().deposit(address(this), collateralAmount_);
        }
    }

    /// @dev Gets collateral balance deposited into Stargate pool. Collateral and LP are, usually, 1:1.
    function _getCollateralInStargate() internal view returns (uint256 _collateralStaked) {
        return lpAmountStaked() + stargateLp().balanceOf(address(this));
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _getCollateralInStargate() + _collateralHere;

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

        // strategy may get new fund. Deposit and stake it to stargate
        _deposit(_collateralToken.balanceOf(address(this)));
        _stakeLp();
    }

    function _stakeLp() internal {
        IERC20 _stargateLp = stargateLp();
        uint256 _lpAmount = _stargateLp.balanceOf(address(this));
        if (_lpAmount > 0) {
            stargateStaking().deposit(_stargateLp, _lpAmount);
        }
    }

    function _unstakeLp(uint256 lpRequired_) internal {
        IERC20 _stargateLp = stargateLp();
        uint256 _lpHere = _stargateLp.balanceOf(address(this));
        if (lpRequired_ > _lpHere) {
            uint256 lpToUnstake_ = lpRequired_ - _lpHere;
            uint256 _lpAmountStaked = lpAmountStaked();
            if (lpToUnstake_ > _lpAmountStaked) {
                lpToUnstake_ = _lpAmountStaked;
            }
            stargateStaking().withdraw(_stargateLp, lpToUnstake_);
        }
    }

    /// @dev Withdraw collateral here. amount_ is collateral amount.
    /// @dev This method may withdraw less than requested amount. Caller may need to check balance before and after
    function _withdrawHere(uint256 amount_) internal override {
        // LP and collateral are 1:1
        _unstakeLp(amount_);

        IStargatePool _stargatePool = stargatePool();
        // Minimum of amount_, available LP and available collateral in Stargate pool.
        amount_ = Math.min(amount_, Math.min(stargateLp().balanceOf(address(this)), _stargatePool.poolBalance()));

        if (amount_ > 0) {
            _stargatePool.redeem(amount_, address(this));
        }
    }
}
