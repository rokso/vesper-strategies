// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategy {
    function rebalance() external returns (uint256 _profit, uint256 _loss, uint256 _payback);

    function sweep(address _fromToken) external;

    function withdraw(uint256 _amount) external;

    function collateralToken() external view returns (IERC20);

    function feeCollector() external view returns (address);

    function isActive() external view returns (bool);

    function isReservedToken(address _token) external view returns (bool);

    function keepers() external view returns (address[] memory);

    function receiptToken() external view returns (address);

    function pool() external view returns (address);

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external view returns (string memory);
}
