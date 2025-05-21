// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapper} from "contracts/interfaces/swapper/ISwapper.sol";
import {IMasterOracle} from "contracts/interfaces/one-oracle/IMasterOracle.sol";

contract SwapperMock is ISwapper, Test {
    uint256 slippage;
    IMasterOracle masterOracle;

    function updateSlippage(uint256 slippage_) external {
        slippage = slippage_;
    }

    constructor(IMasterOracle masterOracle_) {
        masterOracle = masterOracle_;
    }

    function swapExactInput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address receiver_
    ) external returns (uint256 _amountOut) {
        require(
            IERC20(tokenIn_).allowance(msg.sender, address(this)) >= amountIn_,
            "SwapperMock: Not enough tokenIn approved"
        );
        IERC20(tokenIn_).transferFrom(msg.sender, address(this), amountIn_);
        _amountOut = (masterOracle.quote(tokenIn_, tokenOut_, amountIn_) * (1e18 - slippage)) / 1e18;
        require(_amountOut >= amountOutMin_, "SwapperMock: Slippage too high");
        // require(IERC20(tokenOut_).balanceOf(address(this)) >= _amountOut, "SwapperMock: Not enough tokenOut balance");
        // IERC20(tokenOut_).transfer(receiver_, _amountOut);
        deal(tokenOut_, receiver_, IERC20(tokenOut_).balanceOf(receiver_) + _amountOut);
    }

    function getAmountIn(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_
    ) external override returns (uint256 _amountIn) {}

    function getAmountOut(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_
    ) external returns (uint256 _amountOut) {}

    function swapExactOutput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address receiver_
    ) external override returns (uint256 _amountIn) {}

    function getAllExchanges() external view returns (address[] memory) {}
}
