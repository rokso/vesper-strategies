// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

interface ISwapperManagement {
    function setExactOutputRouting(
        address tokenIn_,
        address tokenOut_,
        address exchange_,
        bytes calldata path_
    ) external;

    function setExactInputRouting(address tokenIn_, address tokenOut_, bytes memory _newRouting) external;

    function governor() external view returns (address);
}
