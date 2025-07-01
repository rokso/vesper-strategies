// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {AaveV3SommelierBorrow, ICellar} from "contracts/strategies/aave/v3/AaveV3SommelierBorrow.sol";
import {ILendingPool} from "contracts/interfaces/aave/ILendingPool.sol";
import {IAToken} from "contracts/interfaces/aave/IAToken.sol";
import {StrategyBorrow_Rebalance_Test} from "test/StrategyBorrow.rebalance.t.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";

abstract contract AaveV3SommelierBorrow_Test is
    Strategy_Withdraw_Test,
    Strategy_Rebalance_Test,
    StrategyBorrow_Rebalance_Test
{
    function _waitForUnlockTime() internal override {
        uint256 _unlockTime = AaveV3SommelierBorrow(address(strategy)).unlockTime();
        if (block.timestamp < _unlockTime) {
            vm.warp(_unlockTime);
        }
    }

    function _increaseCollateralDeposit(uint256 amount) internal virtual override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _lendingPool = AaveV3SommelierBorrow(address(strategy)).aavePoolAddressesProvider().getPool();

        _increaseTokenBalance(amount);

        vm.startPrank(address(strategy));

        _lendingPool.supply(address(strategy.collateralToken()), amount, address(strategy), 0);

        vm.stopPrank();
    }

    function _decreaseCollateralDeposit(uint256 amount) internal virtual override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _lendingPool = AaveV3SommelierBorrow(address(strategy)).aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        _lendingPool.withdraw(address(strategy.collateralToken()), amount, address(strategy));
        _decreaseTokenBalance(amount);
        vm.stopPrank();
    }

    function _increaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        AaveV3SommelierBorrow _strategy = AaveV3SommelierBorrow(address(strategy));
        ILendingPool _lendingPool = _strategy.aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        _lendingPool.borrow(_strategy.borrowToken(), amount, 2, 0, address(strategy));
        _decreaseBorrowBalance(amount);
        vm.stopPrank();
    }

    function _decreaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        AaveV3SommelierBorrow _strategy = AaveV3SommelierBorrow(address(strategy));
        ILendingPool _lendingPool = _strategy.aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        _lendingPool.repay(address(_strategy.borrowToken()), amount, 2, address(strategy));
        vm.stopPrank();
    }

    function _increaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        ICellar _cellar = AaveV3SommelierBorrow(address(strategy)).cellar();

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        _cellar.deposit(amount, address(strategy));
        vm.stopPrank();
    }

    function _decreaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        AaveV3SommelierBorrow _strategy = AaveV3SommelierBorrow(address(strategy));
        ICellar _cellar = _strategy.cellar();
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());

        uint256 _borrowDepositBefore = _getBorrowDeposit();
        _waitForUnlockTime();
        // Due to _waitForUnlockTime, borrowDeposit may change.
        uint256 _borrowDepositAfter = _getBorrowDeposit();
        // if borrowDeposit is increased then we need to withdraw the increased balance as well.
        if (_borrowDepositAfter > _borrowDepositBefore) {
            amount = amount + _borrowDepositAfter - _borrowDepositBefore;
        }
        // withdraw minimum of available and amount
        amount = Math.min(_borrowDepositAfter, amount);

        vm.startPrank(address(strategy));
        uint256 _before = _borrowToken.balanceOf(address(strategy));
        _cellar.withdraw(amount, address(strategy), address(strategy));
        uint256 _withdrawn = _borrowToken.balanceOf(address(strategy)) - _before;
        _decreaseBorrowBalance(_withdrawn);
        vm.stopPrank();
    }

    function _rebalanceBorrow() internal override {
        _adjustBorrowForNoLoss();
    }

    function _getCollateralDeposit() internal view virtual override returns (uint256) {
        return IERC20(strategy.receiptToken()).balanceOf(address(strategy));
    }

    function _getBorrowDebt() internal view override returns (uint256) {
        IAToken _vdToken = AaveV3SommelierBorrow(address(strategy)).vdToken();
        return _vdToken.balanceOf(address(strategy));
    }

    function _getBorrowDeposit() internal view override returns (uint256) {
        ICellar _cellar = AaveV3SommelierBorrow(address(strategy)).cellar();
        return _cellar.convertToAssets(_cellar.balanceOf(address(strategy)));
    }

    function _getMaxBorrowableInCollateral() internal view virtual override returns (uint256) {
        AaveV3SommelierBorrow _strategy = AaveV3SommelierBorrow(address(strategy));

        // _collateralFactor in 4 decimal. 10_000 = 100%
        (, uint256 _collateralFactor, , , , , , , , ) = _strategy
            .aavePoolAddressesProvider()
            .getPoolDataProvider()
            .getReserveConfigurationData(address(strategy.collateralToken()));

        return (_getCollateralDeposit() * _collateralFactor) / MAX_BPS;
    }
}
