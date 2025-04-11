// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

interface IAaveOracle {
    function getAssetPrice(address _asset) external view returns (uint256);
}
