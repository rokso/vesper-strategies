// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {CompoundV3VesperBorrow, IVesperPool} from "contracts/strategies/compound/v3/CompoundV3VesperBorrow.sol";
import {IComet} from "contracts/strategies/compound/v3/CompoundV3.sol";
import {StrategyBorrow_Rebalance_Test} from "test/StrategyBorrow.rebalance.t.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaLINK, COMP, rewards, cUSDCv3, USDC, vaUSDC} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract CompoundV3VesperBorrow_Ethereum_Test is
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

        strategy = new CompoundV3VesperBorrow();
        deinitialize(address(strategy));
        CompoundV3VesperBorrow(payable(address(strategy))).initialize(
            vaLINK,
            SWAPPER,
            rewards,
            COMP,
            cUSDCv3,
            USDC,
            vaUSDC,
            ""
        );
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

        IComet _comet = CompoundV3VesperBorrow(payable(address(strategy))).comet();

        vm.startPrank(address(strategy));
        _increaseCollateralBalance(amount);
        _comet.supply(address(strategy.collateralToken()), amount);
        vm.stopPrank();
    }

    function _decreaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        IComet _comet = CompoundV3VesperBorrow(payable(address(strategy))).comet();
        IERC20 _collateralToken = strategy.collateralToken();

        vm.startPrank(address(strategy));
        _comet.withdraw(address(_collateralToken), amount);
        _decreaseCollateralBalance(amount);
        vm.stopPrank();
    }

    function _increaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));
        IComet _comet = _strategy.comet();

        vm.startPrank(address(strategy));
        _comet.withdraw(_strategy.borrowToken(), amount);
        _decreaseBorrowBalance(amount);
        vm.stopPrank();
    }

    function _decreaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));
        IComet _comet = _strategy.comet();
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        _comet.supply(address(_borrowToken), amount);
        vm.stopPrank();
    }

    function _increaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        IVesperPool _vPool = CompoundV3VesperBorrow(payable(address(strategy))).vPool();

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        _vPool.deposit(amount);
        vm.stopPrank();
    }

    function _decreaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));
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
        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));
        IERC20 _collateralToken = strategy.collateralToken();
        IComet _comet = _strategy.comet();

        return _comet.collateralBalanceOf(address(strategy), address(_collateralToken));
    }

    function _getBorrowDebt() internal view override returns (uint256) {
        IComet _comet = CompoundV3VesperBorrow(payable(address(strategy))).comet();
        return _comet.borrowBalanceOf(address(strategy));
    }

    function _getBorrowDeposit() internal view override returns (uint256) {
        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));
        IVesperPool _vPool = _strategy.vPool();
        return (_vPool.balanceOf(address(strategy)) * _vPool.pricePerShare()) / 1e18;
    }

    function _getMaxBorrowableInCollateral() internal view override returns (uint256) {
        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));
        IComet _comet = _strategy.comet();
        IERC20 _collateralToken = strategy.collateralToken();
        IComet.AssetInfo memory _collateralInfo = _comet.getAssetInfoByAddress(address(_collateralToken));
        return (_getCollateralDeposit() * _collateralInfo.borrowCollateralFactor) / 1e18;
    }
}
