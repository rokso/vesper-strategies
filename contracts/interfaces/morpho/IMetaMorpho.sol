// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMetaMorpho is IERC20 {
    function asset() external view returns (address);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function maxWithdraw(address owner) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
}
