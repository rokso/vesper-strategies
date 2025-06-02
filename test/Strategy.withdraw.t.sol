// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy_Test} from "./Strategy.t.sol";

abstract contract Strategy_Withdraw_Test is Strategy_Test {
    function test_withdraw_fromBalance() public {
        uint256 amount = _poolInitialAmount();

        deal(address(token()), address(strategy), amount);
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool before withdraw");
        assertEq(strategy.tvl(), amount, "tvl before withdraw");

        vm.prank(address(pool));
        strategy.withdraw(amount);

        assertEq(token().balanceOf(address(pool)), amount, "balance of pool after withdraw");
        assertEq(strategy.tvl(), 0, "tvl after withdraw");
    }

    function test_withdraw_fromDeposit() public {
        uint256 amount = _poolInitialAmount();

        pool.updateDebtOfStrategy({target_: amount, latest_: amount});

        deal(address(token()), address(strategy), amount);

        _rebalance();

        uint256 tvl = strategy.tvl();

        assertApproxEqRel(tvl, amount, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");

        _waitForUnlockTime();

        vm.prank(address(pool));
        strategy.withdraw(tvl);

        assertApproxEqRel(
            token().balanceOf(address(pool)),
            tvl,
            MAX_WITHDRAW_SLIPPAGE_REL,
            "balance of pool after withdraw"
        );
        assertApproxEqAbs(strategy.tvl(), 0, MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS, "tvl after withdraw");
    }
}
