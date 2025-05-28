// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy_Test} from "./Strategy.t.sol";

abstract contract Strategy_Rebalance_Test is Strategy_Test {
    function test_rebalance_firstRebalance() public {
        // given
        uint256 initial = _poolInitialAmount();

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        assertEq(strategy.tvl(), 0, "tvl before rebalance");

        // when
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
    }

    function test_rebalance_whenExcessDebtIsZeroAndHasNoProfit() public {
        // given
        uint256 initial = _poolInitialAmount();

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial, latest_: initial});

        // when
        assertEq(pool.excessDebt(address(strategy)), 0, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
    }

    function test_rebalance_whenExcessDebtIsZeroAndHasProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 profit = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial, latest_: initial});
        _makeProfit(profit);
        assertApproxEqRel(strategy.tvl(), initial + profit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl before rebalance");

        // when
        assertEq(pool.excessDebt(address(strategy)), 0, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
            profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenExcessDebtIsZeroAndHasLoss() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 loss = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial, latest_: initial});
        _makeLoss(loss);

        // when
        assertEq(pool.excessDebt(address(strategy)), 0, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial - loss, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }

    function test_rebalance_whenHasExcessDebtAndHasNoProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 excess = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial - excess, latest_: initial});

        // when
        assertEq(pool.excessDebt(address(strategy)), excess, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial - excess, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
            excess,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenHasExcessDebtAndHasProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 excess = (initial * 10_00) / MAX_BPS;
        uint256 profit = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial - excess, latest_: initial});
        _makeProfit(profit);
        assertApproxEqRel(strategy.tvl(), initial + profit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl before rebalance");

        // when
        assertEq(pool.excessDebt(address(strategy)), excess, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial - excess, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
            excess + profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenHasExcessDebtAndHasLoss() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 excess = (initial * 10_00) / MAX_BPS;
        uint256 loss = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial - excess, latest_: initial});
        _makeLoss(loss);

        // when
        assertEq(pool.excessDebt(address(strategy)), excess, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial - excess - loss, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
            excess,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenHasCreditLimitAndHasNoProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 credit = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial + credit);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial + credit, latest_: initial});

        // when
        assertEq(pool.creditLimit(address(strategy)), credit, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial + credit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }

    function test_rebalance_whenHasCreditLimitAndHasProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 credit = (initial * 10_00) / MAX_BPS;
        uint256 profit = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial + credit);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial + credit, latest_: initial});
        _makeProfit(profit);
        assertApproxEqRel(strategy.tvl(), initial + profit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl before rebalance");

        // when
        assertEq(pool.creditLimit(address(strategy)), credit, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial + credit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
            profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenHasCreditLimitAndHasLoss() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 credit = (initial * 10_00) / MAX_BPS;
        uint256 loss = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial + credit);
        pool.updateDebtOfStratregy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStratregy({target_: initial + credit, latest_: initial});
        _makeLoss(loss);

        // when
        assertEq(pool.creditLimit(address(strategy)), credit, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), initial + credit - loss, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertEq(token().balanceOf(address(strategy)), 0, "balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }
}
