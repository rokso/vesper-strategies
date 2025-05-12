// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityGaugeV2} from "../../interfaces/curve/ILiquidityGauge.sol";
import {IConvex, IRewards, IStashTokenWrapper} from "../../interfaces/convex/IConvexForCurve.sol";
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
        address convexToken_,
        IConvex booster_,
        uint256 convexPoolId_
    ) external initializer {
        __CurveBase_init(params_);

        if (convexToken_ == address(0) || address(booster_) == address(0)) revert AddressIsNull();

        (address _lp, , , address _rewards, , ) = booster_.poolInfo(convexPoolId_);
        if (_lp != address(receiptToken())) revert IncorrectLpToken();

        ConvexStorage storage $ = _getConvexStorage();
        $._convexToken = convexToken_;
        $._booster = booster_;
        $._convexRewards = IRewards(_rewards);
        $._convexPoolId = convexPoolId_;

        // set rewardTokens
        _getCurveBaseStorage()._rewardTokens = _getRewardTokens();
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

    /// @dev Return values are not being used hence returning 0
    function _claimRewards() internal override returns (address, uint256) {
        if (!convexRewards().getReward(address(this), true)) revert RewardClaimFailed();
        return (address(0), 0);
    }

    function _getRewardToken(uint256 index_) private view returns (address) {
        address _rewardToken = IRewards(convexRewards().extraRewards(index_)).rewardToken();
        // Convex has some token wrappers which aren't ERC20 tokens but has a token function.
        // Checking allowance will revert if the token is not an ERC20 token.
        try IERC20(_rewardToken).allowance(address(this), address(swapper())) {} catch {
            _rewardToken = IStashTokenWrapper(_rewardToken).token();
        }
        return _rewardToken;
    }

    /**
     * @notice Add reward tokens
     * The Convex pools have CRV and CVX as base rewards and may have others tokens as extra rewards
     * In some cases, CVX is also added as extra reward, reason why we have to ensure to not add it twice
     * @return _rewardTokens The array of reward tokens (both base and extra rewards)
     */
    function _getRewardTokens() internal view override returns (address[] memory _rewardTokens) {
        address _curveToken = curveToken();
        address _convexToken = convexToken();
        uint256 _extraRewardCount;
        uint256 _length = convexRewards().extraRewardsLength();

        for (uint256 i; i < _length; i++) {
            address _rewardToken = _getRewardToken(i);
            // CRV and CVX are default rewardTokens and should not be counted again
            if (_rewardToken != _curveToken && _rewardToken != _convexToken) {
                _extraRewardCount++;
            }
        }

        _rewardTokens = new address[](_extraRewardCount + 2);
        _rewardTokens[0] = _curveToken;
        _rewardTokens[1] = _convexToken;
        uint256 _nextIdx = 2;

        for (uint256 i; i < _length; i++) {
            address _rewardToken = _getRewardToken(i);
            // CRV and CVX already added in array
            if (_rewardToken != _curveToken && _rewardToken != _convexToken) {
                _rewardTokens[_nextIdx++] = _rewardToken;
            }
        }
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
