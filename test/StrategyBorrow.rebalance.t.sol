// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
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

    /// @dev Increase `strategy.borrowToken()` balance
    function _increaseBorrowBalance(uint256 amount) internal virtual {
        require(amount > 0, "amount should be greater than 0");

        IBorrowStrategy _strategy = IBorrowStrategy(payable(address(strategy)));
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());

        deal(address(_borrowToken), address(strategy), _borrowToken.balanceOf(address(strategy)) + amount);
    }

    /// @dev Decrease `strategy.borrowToken()` balance
    function _decreaseBorrowBalance(uint256 amount) internal virtual {
        require(amount > 0, "amount should be greater than 0");

        IBorrowStrategy _strategy = IBorrowStrategy(payable(address(strategy)));
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());
        uint _balance = _borrowToken.balanceOf(address(strategy));
        require(_balance >= amount, "not enough borrow balance to decrease");

        deal(address(_borrowToken), address(strategy), _balance - amount);
    }

    /// @dev Increase `strategy.borrowToken()` debt
    function _increaseBorrowDebt(uint256 amount) internal virtual;

    /// @dev Decrease `strategy.borrowToken()` debt
    function _decreaseBorrowDebt(uint256 amount) internal virtual;

    /// @dev Increase `strategy.borrowToken()` deposit
    function _increaseBorrowDeposit(uint256 amount) internal virtual;

    /// @dev Decrease `strategy.borrowToken()` deposit
    function _decreaseBorrowDeposit(uint256 amount) internal virtual;

    /// @dev Get `strategy.pool().token()` balance
    function _getTokenBalance() internal view virtual returns (uint256) {
        return token().balanceOf(address(strategy));
    }

    /// @dev Get `strategy.collateral()` deposit
    function _getCollateralDeposit() internal view virtual returns (uint256);

    /// @dev Get `strategy.borrowToken()` balance
    function _getBorrowBalance() internal view virtual returns (uint256) {
        IBorrowStrategy _strategy = IBorrowStrategy(payable(address(strategy)));
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());
        return _borrowToken.balanceOf(address(strategy));
    }

    /// @dev Get `strategy.borrowToken()` debt
    function _getBorrowDebt() internal view virtual returns (uint256);

    /// @dev Get `strategy.borrowToken()` deposit
    function _getBorrowDeposit() internal view virtual returns (uint256);

    /// @dev Use collateral factor to get maximum borrowable amount in `strategy.collateral()`
    function _getMaxBorrowableInCollateral() internal view virtual returns (uint256);

    /// @dev Get max amount borrowable in `strategy.borrowToken()`
    function _getBorrowable() internal view virtual returns (uint256) {
        IMasterOracle _oracle = strategy.swapper().masterOracle();
        // In case of high value collateralToken and low value borrowToken
        // _borrowable can be huge, so cap it to max 100.
        uint256 _borrowable = _oracle.quote(
            address(token()),
            IBorrowStrategy(address(strategy)).borrowToken(),
            _getMaxBorrowableInCollateral()
        );

        return Math.min(_borrowable, parseBorrowAmount(100));
    }

    function _getTotalBorrowBalance() internal view returns (uint256) {
        return _getBorrowDeposit() + _getBorrowBalance();
    }

    /// @dev Adjust debt to ensure `strategy.borrowToken()` balance is enough for repayment
    function _adjustBorrowForNoLoss() internal {
        uint256 _borrowDebt = _getBorrowDebt();
        uint256 _totalBorrowBalance = _getTotalBorrowBalance();
        if (_borrowDebt > _totalBorrowBalance) {
            assertApproxEqRel(_borrowDebt, _totalBorrowBalance, 0.0003e18, "borrow loss should be dust");
            _decreaseBorrowDebt(_borrowDebt - _totalBorrowBalance);
        }
    }

    /// @dev Use current `strategy.pool().token()` balance to deposit `strategy.collateral()`
    function _depositCollateral(uint256 tokenAmount) internal {
        _decreaseTokenBalance(tokenAmount);
        _increaseCollateralDeposit(tokenAmount);
    }

    /// @dev Use current `strategy.collateral()` deposit to withdraw `strategy.pool().token()`
    function _withdrawCollateral(uint256 tokenAmount) internal {
        _decreaseCollateralDeposit(tokenAmount);
        _increaseTokenBalance(tokenAmount);
    }

    /// @dev Borrow `strategy.borrowToken()`
    function _borrow(uint256 amount) internal {
        _increaseBorrowDebt(amount);
        _increaseBorrowBalance(amount);
    }

    /// @dev Repay `strategy.borrowToken()`
    function _repay(uint256 amount) internal {
        _adjustBorrowForNoLoss();
        _decreaseBorrowDebt(amount);
        _decreaseBorrowBalance(amount);
    }

    /// @dev Deposit `strategy.borrowToken()` (e.g. BorrowVesper strategies)
    function _depositBorrow(uint256 amount) internal {
        _decreaseBorrowBalance(amount);
        _increaseBorrowDeposit(amount);
    }

    /// @dev Withdraw `strategy.borrowToken()` (e.g. BorrowVesper strategies)
    function _withdrawBorrow(uint256 amount) internal {
        _decreaseBorrowDeposit(amount);
        _increaseBorrowBalance(amount);
    }

    function test_utils() external {
        _increaseTokenBalance(parseAmount(100));
        assertApproxEqAbs(_getTokenBalance(), parseAmount(100), 3, "collateral balance (1)");

        _depositCollateral(parseAmount(10));

        assertApproxEqAbs(_getTokenBalance(), parseAmount(90), 3, "collateral balance (2)");

        _depositCollateral(parseAmount(50));

        assertApproxEqAbs(_getTokenBalance(), parseAmount(40), 4, "collateral balance (3)");
        assertApproxEqAbs(_getCollateralDeposit(), parseAmount(60), 3, "collateral deposit (1)");
        uint256 _borrowAmount = _getBorrowable();
        _borrow(_borrowAmount);

        assertApproxEqAbs(_getBorrowDebt(), _borrowAmount, 2, "borrow debt (1)");
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
        // Repay all so that we can withdraw all in next step
        _repay(_getBorrowDebt());

        _withdrawCollateral(_getCollateralDeposit());

        assertApproxEqRel(_getTokenBalance(), parseAmount(100), MAX_DEPOSIT_SLIPPAGE_REL, "collateral balance (4)");
        assertApproxEqAbs(_getCollateralDeposit(), 0, 2, "collateral deposit (2)");
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

        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "given: balance of pool is zero");
        assertApproxEqRel(_tvl, initial, MAX_DEPOSIT_SLIPPAGE_REL, "given: tvl ~eq target");
        assertApproxEqAbs(_tvl, _getCollateralDeposit(), 1, "given: tvl ~eq collateral deposit");
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "given: no collateral balance");
        assertEq(_getBorrowBalance(), 0, "given: no borrow balance");

        pool.updateDebtOfStrategy({target_: initial, latest_: initial});
    }

    function test_rebalance_whenCollateralBalanceIncreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _profit = (_getCollateralDeposit() * 10_00) / MAX_BPS;
        _increaseTokenBalance(_profit);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "no profit goes to the pool after rebalance");
    }

    function test_rebalance_whenBorrowBalanceIncreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _profit = (_getBorrowDeposit() * 10_00) / MAX_BPS;
        _increaseBorrowBalance(_profit);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore, MAX_DEPOSIT_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertGt(token().balanceOf(address(pool)), 0, "profit goes to the pool after rebalance");
    }

    function test_rebalance_whenCollateralBalanceDecreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _loss = (_getCollateralDeposit() * 10_00) / MAX_BPS;
        _withdrawCollateral(_loss * 2);
        _decreaseTokenBalance(_loss);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _loss, MAX_WITHDRAW_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "balance of pool after rebalance");
    }

    function test_rebalance_whenCollateralDepositDecreases() public {
        uint256 _tvlBefore = _given();

        // when
        uint256 _loss = (_getCollateralDeposit() * 10_00) / MAX_BPS;
        _decreaseCollateralDeposit(_loss);
        _rebalance();

        // then
        assertApproxEqRel(strategy.tvl(), _tvlBefore - _loss, MAX_WITHDRAW_SLIPPAGE_REL, "tvl after rebalance");
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "balance of pool after rebalance");
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "balance of pool after rebalance");
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "balance of pool after rebalance");
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqAbs(token().balanceOf(address(pool)), 0, 1, "no profit goes to the pool after rebalance");
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
        assertApproxEqAbs(_getTokenBalance(), 0, 1, "collateral balance of strategy after rebalance");
        assertEq(_getBorrowBalance(), 0, "borrow balance of strategy after rebalance");
        assertApproxEqRel(
            token().balanceOf(address(pool)),
            _profitInCollateral,
            0.02e18,
            "balance of pool after rebalance"
        );
        assertGt(_getBorrowDebt(), _debtBefore, "debt after rebalance");
    }
}
