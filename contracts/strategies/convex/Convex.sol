// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityGaugeV2} from "../../interfaces/curve/ILiquidityGauge.sol";
import {IConvex, IRewards} from "../../interfaces/convex/IConvexForCurve.sol";
import {CurveBase} from "../curve/CurveBase.sol";

// Convex Strategy
contract Convex is CurveBase {
    using SafeERC20 for IERC20;

    error BoosterDepositFailed();
    error IncorrectLpToken();
    error RewardClaimFailed();
    error UnstakeFromConvexFailed();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.Convex
    struct ConvexStorage {
        address _convexToken;
        IConvex _booster;
        IRewards _convexRewards;
        uint256 _convexPoolId;
    }

    bytes32 private constant ConvexStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.Convex")) - 1)) & ~bytes32(uint256(0xff));

    function _getConvexStorage() internal pure returns (ConvexStorage storage $) {
        bytes32 _location = ConvexStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        CurveBase.CurveInitParams memory params_,
        IConvex booster_,
        uint256 convexPoolId_
    ) external initializer {
        __CurveBase_init(params_);

        if (address(booster_) == address(0)) revert AddressIsNull();

        (address _lp, , , address _rewards, , ) = booster_.poolInfo(convexPoolId_);
        if (_lp != address(receiptToken())) revert IncorrectLpToken();

        ConvexStorage storage $ = _getConvexStorage();
        $._booster = booster_;
        $._convexRewards = IRewards(_rewards);
        $._convexPoolId = convexPoolId_;
    }

    function booster() public view returns (IConvex) {
        return _getConvexStorage()._booster;
    }

    function convexPoolId() public view returns (uint256) {
        return _getConvexStorage()._convexPoolId;
    }

    function convexRewards() public view returns (IRewards) {
        return _getConvexStorage()._convexRewards;
    }

    function convexToken() public view returns (address) {
        return _getConvexStorage()._convexToken;
    }

    function lpBalanceStaked() public view override returns (uint256 _total) {
        _total = convexRewards().balanceOf(address(this));
    }

    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        curveLp().forceApprove(address(booster()), amount_);
    }

    function _deposit() internal override {
        // 1. deposit collateral in Curve and stake LP in Curve Gauge.
        super._deposit();

        // 2. Unstake LP from Curve Gauge
        _unstakeLpFromCurve();

        // 3. Stake LP in Convex Booster
        uint256 _balance = curveLp().balanceOf(address(this));
        if (_balance > 0) {
            if (!booster().deposit(convexPoolId(), _balance, true)) revert BoosterDepositFailed();
        }
    }

    function _unstakeLpFromCurve() internal {
        ILiquidityGaugeV2 _curveGauge = curveGauge();
        uint256 _lpStakedInCurve = _curveGauge.balanceOf(address(this));
        if (_lpStakedInCurve > 0) {
            _curveGauge.withdraw(_lpStakedInCurve);
        }
    }

    /// @dev Don't claiming rewards because `_claimRewards()` already does that
    function _unstakeLp(uint256 _amount) internal override {
        if (_amount > 0) {
            if (!convexRewards().withdrawAndUnwrap(_amount, false)) revert UnstakeFromConvexFailed();
        }
    }
}
