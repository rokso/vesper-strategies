// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface ITokenMinter {
    function mint(address gaugeAddr) external;
}
