// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

interface IIncentivesController {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);

    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);

    function claimAllRewards(
        address[] calldata assets,
        address to
    ) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    function getRewardsList() external view returns (address[] memory);
}
