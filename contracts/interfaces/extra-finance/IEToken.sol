// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEToken is IERC20 {
    function lendingPool() external view returns (address);
}
