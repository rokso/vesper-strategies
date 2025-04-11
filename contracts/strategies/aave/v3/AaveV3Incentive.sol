// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IAToken} from "../../../interfaces/aave/IAToken.sol";
import {IIncentivesController} from "../../../interfaces/aave/IIncentivesController.sol";

/// @title This contract provide core operations for Aave v3
library AaveV3Incentive {
    /**
     * @notice Claim rewards from Aave incentive controller
     */
    function _claimRewards(
        address aToken_
    ) internal returns (address[] memory rewardsList, uint256[] memory claimedAmounts) {
        // Some aTokens may have no incentive controller method/variable. Better use try catch
        try IAToken(aToken_).getIncentivesController() returns (IIncentivesController _incentivesController) {
            address[] memory assets = new address[](1);
            assets[0] = address(aToken_);
            return _incentivesController.claimAllRewards(assets, address(this));
            //solhint-disable-next-line no-empty-blocks
        } catch {}
    }
}
