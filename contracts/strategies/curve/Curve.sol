// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {ILiquidityGaugeV2, ILiquidityGaugeReward} from "../../interfaces/curve/ILiquidityGauge.sol";
import {CurveBase} from "./CurveBase.sol";

/// @title This strategy will deposit collateral token in a Curve Pool and earn interest.
// solhint-disable no-empty-blocks
contract Curve is CurveBase {
    function initialize(CurveInitParams memory params_) external initializer {
        __CurveBase_init(params_);
        // set rewardTokens
        _getCurveBaseStorage()._rewardTokens = _getRewardTokens();
    }

    /**
     * @dev Prepare rewardToken array
     * @return _rewardTokens The array of reward tokens (both base and extra rewards)
     */
    function _getRewardTokens() internal view override returns (address[] memory _rewardTokens) {
        address _curveToken = curveToken();
        ILiquidityGaugeV2 _curveGauge = curveGauge();
        _rewardTokens = new address[](1);
        _rewardTokens[0] = _curveToken;

        // If LiquidityGaugeReward, `rewarded_token` only
        try ILiquidityGaugeReward(address(_curveGauge)).rewarded_token() returns (address _rewardToken) {
            _rewardTokens = new address[](2);
            _rewardTokens[0] = _curveToken;
            _rewardTokens[1] = _rewardToken;
            return _rewardTokens;
        } catch {}

        // If LiquidityGaugeV2 or LiquidityGaugeV3, curveToken + extra reward tokens
        try _curveGauge.reward_tokens(0) returns (address _rewardToken) {
            // If no extra reward token then curveToken only
            if (_rewardToken == address(0)) {
                return _rewardTokens;
            }

            try _curveGauge.reward_count() returns (uint256 _len) {
                _rewardTokens = new address[](1 + _len);
                _rewardTokens[0] = _rewardToken;
                for (uint256 i = 1; i < _len; ++i) {
                    _rewardTokens[i] = _curveGauge.reward_tokens(i);
                }
                _rewardTokens[_len] = _curveToken;
                return _rewardTokens;
            } catch {
                // If doesn't implement `reward_count` then only _rewardToken is extra
                // E.g. stETH pool
                _rewardTokens = new address[](2);
                _rewardTokens[0] = _curveToken;
                _rewardTokens[1] = _rewardToken;
                return _rewardTokens;
            }
        } catch {}

        // If LiquidityGauge, curveToken only
        return _rewardTokens;
    }
}
