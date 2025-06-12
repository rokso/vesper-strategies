// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {AaveV3VesperBorrow, IVesperPool} from "contracts/strategies/aave/v3/AaveV3VesperBorrow.sol";
import {ILendingPool} from "contracts/interfaces/aave/ILendingPool.sol";
import {IAToken} from "contracts/interfaces/aave/IAToken.sol";
import {IAaveOracle} from "contracts/interfaces/aave/IAaveOracle.sol";
import {StrategyBorrow_Rebalance_Test} from "test/StrategyBorrow.rebalance.t.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {vaETH, vaUSDC, aEthWETH, USDC, AAVE_V3_POOL_ADDRESSES_PROVIDER} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract AaveV3VesperBorrow_Ethereum_Test is
    Strategy_Withdraw_Test,
    Strategy_Rebalance_Test,
    StrategyBorrow_Rebalance_Test
{
    constructor() {
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0000000001e18;
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000000001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        address _borrowToken = USDC;
        strategy = new AaveV3VesperBorrow();
        deinitialize(address(strategy));
        AaveV3VesperBorrow(payable(address(strategy))).initialize(
            vaETH,
            address(swapperMock),
            aEthWETH,
            _borrowToken,
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            vaUSDC,
            ""
        );

        address _collateralToken = address(strategy.collateralToken());
        IAaveOracle _oracle = AaveV3VesperBorrow((address(strategy))).aavePoolAddressesProvider().getPriceOracle();
        uint256 _collateralPrice = _oracle.getAssetPrice(_collateralToken);
        uint256 _borrowTokenPrice = _oracle.getAssetPrice(_borrowToken);
        // Set WETH price 8 decimals
        masterOracleMock.updatePrice(_collateralToken, _collateralPrice);
        // Set USDC price 8 decimals
        masterOracleMock.updatePrice(_borrowToken, _borrowTokenPrice);
    }

    function _makeLoss(uint256 loss) internal override {
        _decreaseCollateralDeposit(loss);
    }

    function _makeProfit(uint256 profit) internal override {
        _adjustBorrowForNoLoss();
        _increaseCollateralDeposit(profit);
    }

    function _increaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _lendingPool = AaveV3VesperBorrow(payable(address(strategy)))
            .aavePoolAddressesProvider()
            .getPool();

        vm.startPrank(address(strategy));
        _increaseCollateralBalance(amount);
        _lendingPool.supply(address(strategy.collateralToken()), amount, address(strategy), 0);
        vm.stopPrank();
    }

    function _decreaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _lendingPool = AaveV3VesperBorrow(payable(address(strategy)))
            .aavePoolAddressesProvider()
            .getPool();

        vm.startPrank(address(strategy));
        _lendingPool.withdraw(address(strategy.collateralToken()), amount, address(strategy));
        _decreaseCollateralBalance(amount);
        vm.stopPrank();
    }

    function _increaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        AaveV3VesperBorrow _strategy = AaveV3VesperBorrow(payable(address(strategy)));
        ILendingPool _lendingPool = _strategy.aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        _lendingPool.borrow(_strategy.borrowToken(), amount, 2, 0, address(strategy));
        _decreaseBorrowBalance(amount);
        vm.stopPrank();
    }

    function _decreaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        AaveV3VesperBorrow _strategy = AaveV3VesperBorrow(payable(address(strategy)));
        ILendingPool _lendingPool = _strategy.aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        _lendingPool.repay(address(_strategy.borrowToken()), amount, 2, address(strategy));
        vm.stopPrank();
    }

    function _increaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        IVesperPool _vPool = AaveV3VesperBorrow(payable(address(strategy))).vPool();

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        _vPool.deposit(amount);
        vm.stopPrank();
    }

    function _decreaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        AaveV3VesperBorrow _strategy = AaveV3VesperBorrow(payable(address(strategy)));
        IVesperPool _vPool = _strategy.vPool();
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());

        uint256 _pricePerShare = _vPool.pricePerShare();
        uint256 _shares = (amount * 1e18) / _pricePerShare;
        _shares = amount > ((_shares * _pricePerShare) / 1e18) ? _shares + 1 : _shares;

        vm.startPrank(address(strategy));
        uint256 _before = _borrowToken.balanceOf(address(strategy));
        _vPool.withdraw(_shares);
        uint256 _withdrawn = _borrowToken.balanceOf(address(strategy)) - _before;
        _decreaseBorrowBalance(_withdrawn);
        vm.stopPrank();
    }

    function _rebalanceBorrow() internal override {
        _adjustBorrowForNoLoss();
    }

    function _getCollateralDeposit() internal view override returns (uint256) {
        return IERC20(strategy.receiptToken()).balanceOf(address(strategy));
    }

    function _getBorrowDebt() internal view override returns (uint256) {
        IAToken _vdToken = AaveV3VesperBorrow(payable(address(strategy))).vdToken();
        return _vdToken.balanceOf(address(strategy));
    }

    function _getBorrowDeposit() internal view override returns (uint256) {
        IVesperPool _vPool = AaveV3VesperBorrow(payable(address(strategy))).vPool();
        return (_vPool.balanceOf(address(strategy)) * _vPool.pricePerShare()) / 1e18;
    }

    function _getMaxBorrowableInCollateral() internal view override returns (uint256) {
        AaveV3VesperBorrow _strategy = AaveV3VesperBorrow(payable(address(strategy)));

        // _collateralFactor in 4 decimal. 10_000 = 100%
        (, uint256 _collateralFactor, , , , , , , , ) = _strategy
            .aavePoolAddressesProvider()
            .getPoolDataProvider()
            .getReserveConfigurationData(address(strategy.collateralToken()));

        return (_getCollateralDeposit() * _collateralFactor) / MAX_BPS;
    }
}
