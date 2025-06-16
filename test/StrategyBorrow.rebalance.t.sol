// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMasterOracle} from "contracts/interfaces/one-oracle/IMasterOracle.sol";
import {Strategy_Test} from "./Strategy.t.sol";

interface IBorrowStrategy {
    function maxBorrowLimit() external view returns (uint256);

    function minBorrowLimit() external view returns (uint256);

    function borrowToken() external view returns (address);
}

abstract contract StrategyBorrow_Rebalance_Test is Strategy_Test {
    function parseBorrowAmount(uint256 amount) internal view returns (uint256) {
        IBorrowStrategy _strategy = IBorrowStrategy(payable(address(strategy)));
        IERC20Metadata _borrowToken = IERC20Metadata(_strategy.borrowToken());
        return amount * 10 ** _borrowToken.decimals();
    }

    function _increaseCollateralBalance(uint256 amount) internal virtual {
        require(amount > 0, "amount should be greater than 0");

        IERC20 _collateralToken = strategy.collateralToken();

        deal(address(_collateralToken), address(strategy), _collateralToken.balanceOf(address(strategy)) + amount);
    }

    function _decreaseCollateralBalance(uint256 amount) internal virtual {
        require(amount > 0, "amount should be greater than 0");

        IERC20 _collateralToken = strategy.collateralToken();
        uint _balance = _collateralToken.balanceOf(address(strategy));
        require(_balance >= amount, "no enough balance to decrease");

        deal(address(_collateralToken), address(strategy), _balance - amount);
    }

    function _increaseCollateralDeposit(uint256 amount) internal virtual;

    function _decreaseCollateralDeposit(uint256 amount) internal virtual;

    function _increaseBorrowBalance(uint256 amount) internal virtual {
        require(amount > 0, "amount should be greater than 0");

        IBorrowStrategy _strategy = IBorrowStrategy(payable(address(strategy)));
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());

        deal(address(_borrowToken), address(strategy), _borrowToken.balanceOf(address(strategy)) + amount);
    }

    function _decreaseBorrowBalance(uint256 amount) internal virtual {
        require(amount > 0, "amount should be greater than 0");

        IBorrowStrategy _strategy = IBorrowStrategy(payable(address(strategy)));
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());
        uint _balance = _borrowToken.balanceOf(address(strategy));
        require(_balance >= amount, "no enough balance to decrease");

        deal(address(_borrowToken), address(strategy), _balance - amount);
    }

    function _increaseBorrowDebt(uint256 amount) internal virtual;

    function _decreaseBorrowDebt(uint256 amount) internal virtual;

    function _increaseBorrowDeposit(uint256 amount) internal virtual;

    function _decreaseBorrowDeposit(uint256 amount) internal virtual;

    function _getCollateralBalance() internal view virtual returns (uint256) {
        return strategy.collateralToken().balanceOf(address(strategy));
    }

    function _getCollateralDeposit() internal view virtual returns (uint256);

    function _getBorrowBalance() internal view virtual returns (uint256) {
        IBorrowStrategy _strategy = IBorrowStrategy(payable(address(strategy)));
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());
        return _borrowToken.balanceOf(address(strategy));
    }

    function _getBorrowDebt() internal view virtual returns (uint256);

    function _getBorrowDeposit() internal view virtual returns (uint256);

    function _getMaxBorrowableInCollateral() internal view virtual returns (uint256);

    function _getBorrowable() internal view virtual returns (uint256) {
        IMasterOracle _oracle = strategy.swapper().masterOracle();
        // In case of high value collateralToken and low value borrowToken
        // _borrowable can be huge, so cap it to max 100.
        uint256 _borrowable = _oracle.quote(
            address(strategy.collateralToken()),
            IBorrowStrategy(address(strategy)).borrowToken(),
            _getMaxBorrowableInCollateral()
        );

        return Math.min(_borrowable, parseBorrowAmount(100));
    }

    function _getTotalBorrowBalance() internal view returns (uint256) {
        return _getBorrowDeposit() + _getBorrowBalance();
    }

    /**
     * There can be scenarios when borrow is in loss. In such cases, rebalance
     * would swap collateral for borrow. For test purpose, we want to keep
     * accounting of the collateral balance fixed and therefore avoid swap.
     */
    function _adjustBorrowForNoLoss() internal {
        uint256 _borrowDebt = _getBorrowDebt();
        uint256 _totalBorrowBalance = _getTotalBorrowBalance();
        if (_borrowDebt > _totalBorrowBalance) {
            _increaseBorrowBalance(_borrowDebt - _totalBorrowBalance);
        }
    }

    function _depositCollateral(uint256 amount) internal {
        _decreaseCollateralBalance(amount);
        _increaseCollateralDeposit(amount);
    }

    function _withdrawCollateral(uint256 amount) internal {
        _decreaseCollateralDeposit(amount);
        _increaseCollateralBalance(amount);
    }

    function _borrow(uint256 amount) internal {
        _increaseBorrowDebt(amount);
        _increaseBorrowBalance(amount);
    }

    function _repay(uint256 amount) internal {
        _decreaseBorrowDebt(amount);
        _decreaseBorrowBalance(amount);
    }

    function _depositBorrow(uint256 amount) internal {
        _decreaseBorrowBalance(amount);
        _increaseBorrowDeposit(amount);
    }

    function _withdrawBorrow(uint256 amount) internal {
        _decreaseBorrowDeposit(amount);
        _increaseBorrowBalance(amount);
    }

    function test_utils() external {
        _increaseCollateralBalance(parseAmount(100));
        assertApproxEqAbs(_getCollateralBalance(), parseAmount(100), 1, "collateral balance (1)");

        _depositCollateral(parseAmount(10));

        assertEq(_getCollateralBalance(), parseAmount(90), "collateral balance (2)");

        _depositCollateral(parseAmount(50));

        assertEq(_getCollateralBalance(), parseAmount(40), "collateral balance (3)");
        assertApproxEqAbs(_getCollateralDeposit(), parseAmount(60), 1, "collateral deposit (1)");
        uint256 _borrowAmount = _getBorrowable();
        _borrow(_borrowAmount);

        assertApproxEqAbs(_getBorrowDebt(), _borrowAmount, 1, "borrow debt (1)");
        assertEq(_getBorrowBalance(), _borrowAmount, "borrow balance (1)");

        uint256 _repayAmount = _borrowAmount / 2; // repay half of borrow
        _repay(_repayAmount);

        assertApproxEqAbs(_getBorrowDebt(), _repayAmount, 2, "borrow debt (2)");
        assertApproxEqAbs(_getBorrowBalance(), _repayAmount, 1, "borrow balance (2)");

        // Borrowed X and then repaid Y, so remaining in strategy is X-Y. This can be deposited in end protocol.
        uint256 _depositBorrowAmount = _borrowAmount - _repayAmount;
        _depositBorrow(_depositBorrowAmount);

        assertApproxEqAbs(_getBorrowBalance(), 0, 1, "borrow balance (3)");
        assertApproxEqAbs(_getBorrowDeposit(), _depositBorrowAmount, 1, "borrow deposit (1)");

        _withdrawBorrow(_depositBorrowAmount);
        // Adjust for loss in borrow without this repay all will not be possible
        _adjustBorrowForNoLoss();
        // Repay all so that we can withdraw all in next step
        _repay(_getBorrowDebt());

        _withdrawCollateral(_getCollateralDeposit());

        assertApproxEqAbs(_getCollateralBalance(), parseAmount(100), 1, "collateral balance (4)");
        assertEq(_getCollateralDeposit(), 0, "collateral deposit (2)");
        assertApproxEqAbs(_getBorrowBalance(), 0, 1, "borrow balance (4)");
        assertEq(_getBorrowDebt(), 0, "borrow debt (3)");
        assertEq(_getBorrowDeposit(), 0, "borrow deposit (2)");
    }

    function _given() internal returns (uint256 _tvl) {
        uint256 initial = _poolInitialAmount();
        deal(address(token()), address(pool), initial);

        pool.updateDebtOfStrategy({target_: initial, latest_: 0});

        _rebalance();

        _tvl = strategy.tvl();

        assertEq(token().balanceOf(address(pool)), 0, "given: balance of pool is zero");
        assertApproxEqRel(_tvl, _getWrappedAmount(initial), MAX_DEPOSIT_SLIPPAGE_REL, "given: tvl ~eq target");
        assertApproxEqAbs(_tvl, _getCollateralDeposit(), 1, "given: tvl ~eq collateral deposit");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "given: no collateral balance");
        assertEq(_getBorrowBalance(), 0, "given: no borrow balance");

        pool.updateDebtOfStrategy({target_: initial, latest_: initial});
        _adjustBorrowForNoLoss();
    }

    function test_rebalance_whenCollateralBalanceIncreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _profit = (_getCollateralDeposit() * 10_00) / MAX_BPS;
        _increaseCollateralBalance(_profit);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            _getWrappedAmount(token().balanceOf(address(pool))),
            _profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "profit goes to the pool after rebalance"
        );
    }

    function test_rebalance_whenCollateralDepositIncreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _profit = (_getCollateralDeposit() * 10_00) / MAX_BPS;
        _increaseCollateralDeposit(_profit);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            _getWrappedAmount(token().balanceOf(address(pool))),
            _profit,
            MAX_DEPOSIT_SLIPPAGE_REL,
            "profit goes to the pool after rebalance"
        );
    }

    function test_rebalance_whenBorrowDebtIncreases() public {
        IBorrowStrategy _s = IBorrowStrategy(address(strategy));
        uint256 _tvlBefore = _given();

        // when
        uint256 _borrowed = _getBorrowDebt();
        uint256 _loss = (_borrowed * 10_00) / MAX_BPS;
        uint256 _borrowedInCollateral = (_getMaxBorrowableInCollateral() * _s.minBorrowLimit()) / MAX_BPS;
        uint256 _lossInCollateral = (_borrowedInCollateral * 10_00) / MAX_BPS;

        _increaseBorrowDebt(_loss);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _lossInCollateral, 0.015e18, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "no profit goes to the pool after rebalance");
    }

    function test_rebalance_whenBorrowBalanceIncreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _profit = (_getBorrowDeposit() * 10_00) / MAX_BPS;
        _increaseBorrowBalance(_profit);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertGt(token().balanceOf(address(pool)), 0, "profit goes to the pool after rebalance");
    }

    function test_rebalance_whenBorrowDepositIncreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _profit = (_getBorrowDeposit() * 10_00) / MAX_BPS;
        _increaseBorrowDeposit(_profit);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertGt(token().balanceOf(address(pool)), 0, "profit goes to the pool after rebalance");
    }

    function test_rebalance_whenCollateralBalanceDecreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _loss = (_getCollateralDeposit() * 10_00) / MAX_BPS;
        _withdrawCollateral(_loss * 2);
        _decreaseCollateralBalance(_loss);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _loss, MAX_WITHDRAW_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }

    function test_rebalance_whenCollateralDepositDecreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _loss = (_getCollateralDeposit() * 10_00) / MAX_BPS;
        _decreaseCollateralDeposit(_loss);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _loss, MAX_WITHDRAW_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }

    function test_rebalance_whenBorrowDebtDecreases() public {
        IBorrowStrategy _s = IBorrowStrategy(address(strategy));
        uint256 _tvlBefore = _given();

        // when
        uint256 _borrowed = _getBorrowDebt();
        uint256 _borrowedInCollateral = (_getMaxBorrowableInCollateral() * _s.minBorrowLimit()) / MAX_BPS;
        uint256 _profit = (_borrowed * 10_00) / MAX_BPS;
        uint256 _profitInCollateral = (_borrowedInCollateral * 10_00) / MAX_BPS;
        _decreaseBorrowDebt(_profit);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_WITHDRAW_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            _getWrappedAmount(token().balanceOf(address(pool))),
            _profitInCollateral,
            0.02e18,
            "balance of pool after rebalance"
        );
    }

    function test_rebalance_whenBorrowBalanceDecreases() public {
        IBorrowStrategy _s = IBorrowStrategy(address(strategy));
        uint256 _tvlBefore = _given();

        // when
        uint256 _borrowed = _getBorrowDeposit();
        uint256 _borrowedInCollateral = (_getMaxBorrowableInCollateral() * _s.minBorrowLimit()) / MAX_BPS;
        uint256 _loss = (_borrowed * 10_00) / MAX_BPS;
        uint256 _lossInCollateral = (_borrowedInCollateral * 10_00) / MAX_BPS;
        _withdrawBorrow(_loss * 2);
        _decreaseBorrowBalance(_loss);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _lossInCollateral, 0.015e18, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }

    function test_rebalance_whenBorrowDepositDecreases() public {
        IBorrowStrategy _s = IBorrowStrategy(address(strategy));
        uint256 _tvlBefore = _given();

        // when
        uint256 _borrowed = _getBorrowDeposit();
        uint256 _borrowedInCollateral = (_getMaxBorrowableInCollateral() * _s.minBorrowLimit()) / MAX_BPS;
        uint256 _loss = (_borrowed * 10_00) / MAX_BPS;
        uint256 _lossInCollateral = (_borrowedInCollateral * 10_00) / MAX_BPS;
        _decreaseBorrowDeposit(_loss);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _lossInCollateral, 0.015e18, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "balance of pool after rebalance");
    }

    function test_rebalance_whenBorrowDebtIncreasesHigherThanMax() public {
        IBorrowStrategy _s = IBorrowStrategy(address(strategy));
        uint256 _tvlBefore = _given();

        // when
        uint256 _borrowed = _getBorrowDeposit();
        uint256 _borrowedInCollateral = (_getMaxBorrowableInCollateral() * _s.minBorrowLimit()) / MAX_BPS;
        uint256 _loss = (_borrowed * 20_00) / MAX_BPS;
        uint256 _lossInCollateral = (_borrowedInCollateral * 20_00) / MAX_BPS;
        _increaseBorrowDebt(_loss);
        uint256 _debtBefore = _getBorrowDebt();
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _lossInCollateral, 0.015e18, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertEq(token().balanceOf(address(pool)), 0, "no profit goes to the pool after rebalance");
        assertLt(_getBorrowDebt(), _debtBefore, "debt after rebalance");
    }

    function test_rebalance_whenBorrowDebtDecreasesLowerThanMin() public {
        IBorrowStrategy _s = IBorrowStrategy(address(strategy));
        uint256 _tvlBefore = _given();

        // when
        uint256 _borrowed = _getBorrowDeposit();
        uint256 _borrowedInCollateral = (_getMaxBorrowableInCollateral() * _s.minBorrowLimit()) / MAX_BPS;
        uint256 _profit = (_borrowed * 20_00) / MAX_BPS;
        uint256 _profitInCollateral = (_borrowedInCollateral * 20_00) / MAX_BPS;
        _decreaseBorrowDebt(_profit);
        uint256 _debtBefore = _getBorrowDebt();
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_WITHDRAW_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getCollateralBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            _getWrappedAmount(token().balanceOf(address(pool))),
            _profitInCollateral,
            0.02e18,
            "balance of pool after rebalance"
        );
        assertGt(_getBorrowDebt(), _debtBefore, "debt after rebalance");
    }
}
