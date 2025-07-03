// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy_Test} from "./Strategy.t.sol";

abstract contract Strategy_Withdraw_Test is Strategy_Test {
    // This hook will be used by borrow strategy to rebalance borrow
    function _rebalanceBorrow() internal virtual {}

    function test_withdraw_fromBalance() public {
        uint256 amount = _poolInitialAmount();

        deal(address(token()), address(strategy), amount);
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "balance of pool before withdraw");
        assertApproxEqAbs(strategy.tvl(), amount, 5, "tvl before withdraw");

        vm.prank(address(pool));
        strategy.withdraw(amount - MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS);

        assertApproxEqAbs(
            token().balanceOf(address(pool)),
            amount,
            MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS,
            "balance of pool after withdraw"
        );
        assertApproxEqAbs(strategy.tvl(), 0, MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS, "tvl after withdraw");
    }

    function test_withdraw_some_fromDeposit() public {
        uint256 amount = _poolInitialAmount();

        pool.updateDebtOfStrategy({target_: amount, latest_: amount});

        deal(address(token()), address(strategy), amount);

        _rebalance();

        uint256 tvl = strategy.tvl();

        assertApproxEqRel(tvl, amount, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");

        _waitForUnlockTime();

        // Withdraw half of the TVL. Borrow strategies may experience loss and withdrawing
        // whole TVL will fail at repay.
        uint256 amountToWithdraw = tvl / 2;
        vm.prank(address(pool));
        strategy.withdraw(amountToWithdraw);

        assertApproxEqRel(
            token().balanceOf(address(pool)),
            amountToWithdraw,
            MAX_WITHDRAW_SLIPPAGE_REL,
            "balance of pool after withdraw"
        );
        assertApproxEqRel(strategy.tvl(), tvl - amountToWithdraw, MAX_WITHDRAW_SLIPPAGE_REL, "tvl after withdraw");
    }

    function test_withdraw_all_fromDeposit() public {
        uint256 amount = _poolInitialAmount();

        pool.updateDebtOfStrategy({target_: amount, latest_: amount});

        deal(address(token()), address(strategy), amount);

        _rebalance();

        uint256 tvl = strategy.tvl();

        assertApproxEqRel(tvl, amount, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");

        _waitForUnlockTime();
        // There are scenarios when strategy yield profit due to `_waitForUnlockTime`
        tvl = strategy.tvl();
        uint256 _profit = tvl > amount ? tvl - amount : 0;

        // Allow to adjust borrow position before withdrawal of whole TVL (i.e. ensure balance is enough to repay all debt).
        _rebalanceBorrow();
        vm.prank(address(pool));
        strategy.withdraw(amount);

        assertApproxEqRel(
            token().balanceOf(address(pool)),
            tvl,
            MAX_WITHDRAW_SLIPPAGE_REL,
            "balance of pool after withdraw"
        );

        assertApproxEqAbs(strategy.tvl(), _profit, MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS, "tvl after withdraw");
    }
}
