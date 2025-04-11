// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

interface IPoolAccountant {
    function addStrategy(address strategy_, uint256 debtRatio_, uint256 externalDepositFee_) external;

    function getStrategies() external view returns (address[] memory);
}
