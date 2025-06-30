// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {Convex} from "contracts/strategies/convex/Convex.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";

abstract contract Convex_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    function _decreaseCollateralDeposit(uint256 loss) internal override {
        Convex _strategy = Convex(payable(address(strategy)));
        IERC20 _lp = IERC20(_strategy.receiptToken());
        uint256 _lpAmount = (_strategy.lpBalanceStaked() * loss) / _strategy.tvl();

        vm.startPrank(address(strategy));
        _strategy.convexRewards().withdrawAndUnwrap(_lpAmount, false);
        _lp.transfer(address(0xDead), _lpAmount);
        vm.stopPrank();
    }

    function _increaseCollateralDeposit(uint256 profit) internal override {}

    function _makeProfit(uint256 profit) internal override {
        // Increasing `strategy.pool().token()` balance instead of depositing due to its complexity.
        _increaseTokenBalance(profit);
    }

    function _makeLoss(uint256 loss) internal override {
        _decreaseCollateralDeposit(loss);
    }
}
