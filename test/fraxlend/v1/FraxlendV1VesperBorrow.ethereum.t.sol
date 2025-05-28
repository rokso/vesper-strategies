// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {IFraxlendPair} from "contracts/strategies/fraxlend/v1/FraxlendV1.sol";
import {FraxlendV1VesperBorrow, IVesperPool} from "contracts/strategies/fraxlend/v1/FraxlendV1VesperBorrow.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {StrategyBorrow_Rebalance_Test} from "test/StrategyBorrow.rebalance.t.sol";
import {SWAPPER, vaWBTC, vaFRAX, FRAX, FRAXLEND_V1_WBTC_FRAX} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract FraxlendV1VesperBorrow_Ethereum_Test is
    Strategy_Withdraw_Test,
    Strategy_Rebalance_Test,
    StrategyBorrow_Rebalance_Test
{
    function _setUp() internal override {
        vm.createSelectFork({urlOrAlias: "ethereum"});

        strategy = new FraxlendV1VesperBorrow();
        deinitialize(address(strategy));
        FraxlendV1VesperBorrow(address(strategy)).initialize(vaWBTC, SWAPPER, FRAXLEND_V1_WBTC_FRAX, FRAX, vaFRAX, "");
    }

    function _poolInitialAmount() internal pure override returns (uint256) {
        return 0.1e8;
    }

    function _makeLoss(uint256 loss) internal override {
        _decreaseCollateralDeposit(loss);
    }

    function _makeProfit(uint256 profit) internal override {
        _increaseCollateralDeposit(profit);
    }

    function _increaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();
        deal(address(token()), address(this), amount);
        token().approve(address(_pair), amount);
        _pair.addCollateral(amount, address(strategy));
    }

    function _decreaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();

        vm.startPrank(address(strategy));
        _pair.removeCollateral(amount, address(0xDead));
        vm.stopPrank();
    }

    function _increaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");
        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();

        vm.startPrank(address(strategy));
        _pair.borrowAsset(amount, 0, address(0xDead));
        vm.stopPrank();
    }

    function _decreaseBorrowDebt(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");
        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        uint256 _fraxShare = _pair.toBorrowShares(amount, false);
        _pair.repayAsset(_fraxShare, address(strategy));
        vm.stopPrank();
    }

    function _increaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        IVesperPool _vPool = FraxlendV1VesperBorrow(payable(address(strategy))).vPool();

        vm.startPrank(address(strategy));
        _increaseBorrowBalance(amount);
        _vPool.deposit(amount);
        vm.stopPrank();
    }

    function _decreaseBorrowDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        FraxlendV1VesperBorrow _strategy = FraxlendV1VesperBorrow(payable(address(strategy)));
        IVesperPool _vPool = _strategy.vPool();
        IERC20 _borrowToken = IERC20(_strategy.borrowToken());

        uint256 _shares = (amount * 1e18) / _vPool.pricePerShare();

        vm.startPrank(address(strategy));
        uint256 _before = _borrowToken.balanceOf(address(strategy));
        _vPool.withdraw(_shares);
        uint256 _withdrawn = _borrowToken.balanceOf(address(strategy)) - _before;
        _decreaseBorrowBalance(_withdrawn);
        vm.stopPrank();
    }

    function _getCollateralDeposit() internal view override returns (uint256) {
        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();
        return _pair.userCollateralBalance(address(strategy));
    }

    function _getBorrowDebt() internal view override returns (uint256) {
        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();
        return _pair.toBorrowAmount(_pair.userBorrowShares(address(strategy)), true);
    }

    function _getBorrowDeposit() internal view override returns (uint256) {
        FraxlendV1VesperBorrow _strategy = FraxlendV1VesperBorrow(payable(address(strategy)));
        IVesperPool _vPool = _strategy.vPool();
        return (_vPool.balanceOf(address(strategy)) * _vPool.pricePerShare()) / 1e18;
    }

    function _getMaxBorrowableInCollateral() internal view override returns (uint256) {
        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();
        (uint256 _LTV_PRECISION, , , , , , , ) = _pair.getConstants();
        uint256 _maxLtv = _pair.maxLTV();
        return (_getCollateralDeposit() * _maxLtv) / (_LTV_PRECISION);
    }
}
