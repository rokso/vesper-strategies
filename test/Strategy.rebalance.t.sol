// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy_Test} from "./Strategy.t.sol";

abstract contract Strategy_Rebalance_Test is Strategy_Test {
    function test_rebalance_firstRebalance() public {
        // given
        uint256 initial = _poolInitialAmount();

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        assertEq(strategy.tvl(), 0, "tvl before rebalance");

        // when
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _getWrappedAmount(initial), MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
    }

    function test_rebalance_whenExcessDebtIsZeroAndHasNoProfit() public {
        // given
        uint256 initial = _poolInitialAmount();

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial, latest_: initial});

        // when
        assertEq(pool.excessDebt(address(strategy)), 0, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _getWrappedAmount(initial), MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
    }

    function test_rebalance_whenExcessDebtIsZeroAndHasProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 _wrappedInitial = _getWrappedAmount(initial);
        uint256 profit = (_wrappedInitial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial, latest_: initial});
        _makeProfit(profit);
        assertApproxEqRel(strategy.tvl(), _wrappedInitial + profit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl before rebalance");

        // when
        assertEq(pool.excessDebt(address(strategy)), 0, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _wrappedInitial, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
        assertApproxEqRel(
            _getWrappedAmount(token().balanceOf(address(pool))),
            profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenExcessDebtIsZeroAndHasLoss() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 _wrappedInitial = _getWrappedAmount(initial);
        uint256 loss = (_wrappedInitial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial, latest_: initial});
        _makeLoss(loss);

        // when
        assertEq(pool.excessDebt(address(strategy)), 0, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _wrappedInitial - loss, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }

    function test_rebalance_whenHasExcessDebtAndHasNoProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 excess = (initial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial - excess, latest_: initial});

        // when
        assertEq(pool.excessDebt(address(strategy)), excess, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(
            strategy.tvl(),
            _getWrappedAmount(initial - excess),
            MAX_DEPOSIT_SLIPPAGE_REL,
            "tvl after rebalance"
        );
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
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
        uint256 _wrappedExcess = _getWrappedAmount(excess);
        uint256 _wrappedInitial = _getWrappedAmount(initial);
        uint256 profit = (_wrappedInitial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial - excess, latest_: initial});
        _makeProfit(profit);
        assertApproxEqRel(strategy.tvl(), _wrappedInitial + profit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl before rebalance");

        // when
        assertEq(pool.excessDebt(address(strategy)), excess, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(
            strategy.tvl(),
            _wrappedInitial - _wrappedExcess,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "tvl after rebalance"
        );
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
        assertApproxEqRel(
            _getWrappedAmount(token().balanceOf(address(pool))),
            _wrappedExcess + profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenHasExcessDebtAndHasLoss() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 excess = (initial * 10_00) / MAX_BPS;
        uint256 _wrappedInitial = _getWrappedAmount(initial);
        uint256 loss = (_wrappedInitial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial - excess, latest_: initial});
        _makeLoss(loss);

        // when
        assertEq(pool.excessDebt(address(strategy)), excess, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(
            strategy.tvl(),
            _wrappedInitial - _getWrappedAmount(excess) - loss,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "tvl after rebalance"
        );
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
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
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial + credit, latest_: initial});

        // when
        assertEq(pool.creditLimit(address(strategy)), credit, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(
            strategy.tvl(),
            _getWrappedAmount(initial + credit),
            MAX_DEPOSIT_SLIPPAGE_REL,
            "tvl after rebalance"
        );
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "balance of pool after rebalance");
    }

    function test_rebalance_whenHasCreditLimitAndHasProfit() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 credit = (initial * 10_00) / MAX_BPS;
        uint256 _wrappedInitial = _getWrappedAmount(initial);
        uint256 profit = (_wrappedInitial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial + credit);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial + credit, latest_: initial});
        _makeProfit(profit);
        assertApproxEqRel(strategy.tvl(), _wrappedInitial + profit, MAX_DEPOSIT_SLIPPAGE_REL, "tvl before rebalance");

        // when
        assertEq(pool.creditLimit(address(strategy)), credit, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(
            strategy.tvl(),
            _wrappedInitial + _getWrappedAmount(credit),
            MAX_DEPOSIT_SLIPPAGE_REL,
            "tvl after rebalance"
        );
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
        assertApproxEqRel(
            _getWrappedAmount(token().balanceOf(address(pool))),
            profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenHasCreditLimitAndHasLoss() public {
        // given
        uint256 initial = _poolInitialAmount();
        uint256 credit = (initial * 10_00) / MAX_BPS;
        uint256 _wrappedInitial = _getWrappedAmount(initial);
        uint256 loss = (_wrappedInitial * 10_00) / MAX_BPS;

        deal(address(token()), address(pool), initial + credit);
        pool.updateDebtOfStrategy({target_: initial, latest_: 0});
        _rebalance();

        pool.updateDebtOfStrategy({target_: initial + credit, latest_: initial});
        _makeLoss(loss);

        // when
        assertEq(pool.creditLimit(address(strategy)), credit, "excess debt before rebalance");
        _rebalance();

        // then
        assertApproxEqRel(
            strategy.tvl(),
            _wrappedInitial + _getWrappedAmount(credit) - loss,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "tvl after rebalance"
        );
        assertApproxEqAbs(token().balanceOf(address(strategy)), 0, 1, "balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "balance of pool after rebalance");
    }
}
