// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVesperPool} from "../interfaces/vesper/IVesperPool.sol";
import {IPoolRewards} from "../interfaces/vesper/IPoolRewards.sol";
import {ISwapper} from "../interfaces/swapper/ISwapper.sol";

library VesperRewards {
    using SafeERC20 for IERC20;

    function _approveToken(IVesperPool vPool_, ISwapper swapper_, uint256 amount_) internal {
        address _poolRewards = vPool_.poolRewards();
        if (_poolRewards != address(0)) {
            address[] memory _rewardTokens = IPoolRewards(_poolRewards).getRewardTokens();
            uint256 _length = _rewardTokens.length;
            for (uint256 i; i < _length; ++i) {
                // if needed, forceApprove will set approval to zero before setting new value.
                IERC20(_rewardTokens[i]).forceApprove(address(swapper_), amount_);
            }
        }
    }

    function _claimAndSwapRewards(IVesperPool vPool_, ISwapper swapper_, address collateralToken_) internal {
        address _poolRewards = vPool_.poolRewards();
        if (_poolRewards != address(0)) {
            IPoolRewards(_poolRewards).claimReward(address(this));
            address[] memory _rewardTokens = IPoolRewards(_poolRewards).getRewardTokens();
            uint256 _length = _rewardTokens.length;
            for (uint256 i; i < _length; ++i) {
                uint256 _rewardAmount = IERC20(_rewardTokens[i]).balanceOf(address(this));
                if (_rewardAmount > 0 && _rewardTokens[i] != collateralToken_) {
                    try
                        swapper_.swapExactInput(_rewardTokens[i], collateralToken_, _rewardAmount, 1, address(this))
                    {} catch {} //solhint-disable no-empty-blocks
                }
            }
        }
    }
}
