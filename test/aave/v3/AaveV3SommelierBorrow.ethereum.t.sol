// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {ICellar} from "contracts/interfaces/sommelier/ISommelier.sol";
import {AaveV3SommelierBorrow} from "contracts/strategies/aave/v3/AaveV3SommelierBorrow.sol";
import {AaveV3SommelierBorrowForStETH} from "contracts/strategies/aave/v3/AaveV3SommelierBorrowForStETH.sol";
import {ILendingPool} from "contracts/interfaces/aave/ILendingPool.sol";
import {IWstETH} from "contracts/interfaces/lido/IWstETH.sol";
import {AaveV3SommelierBorrow_Test} from "test/aave/v3/AaveV3SommelierBorrow.t.sol";
import {SWAPPER, MASTER_ORACLE, vaETH, vaSTETH, aEthWETH, aEthwstETH, WETH, USDC, stETH, wstETH, AAVE_V3_POOL_ADDRESSES_PROVIDER, SOMMELIER_YIELD_ETH, SOMMELIER_YIELD_USDC} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract AaveV3SommelierBorrow_ETH_USDC_Ethereum_Test is AaveV3SommelierBorrow_Test {
    constructor() {
        MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS = 10;
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0003e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0004e18;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new AaveV3SommelierBorrow();
        deinitialize(address(strategy));
        AaveV3SommelierBorrow(address(strategy)).initialize(
            vaETH,
            address(swapperMock), // TODO: Add missing routings or change tokens
            aEthWETH,
            USDC,
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            SOMMELIER_YIELD_USDC,
            ""
        );

        // Both Aave and Master Oracle get prices from Chainlink
        swapperMock.updateMasterOracle(MASTER_ORACLE);

        // USDC cellar has lockPeriod as 86,400 which is same as oracle heartbeat and we get stale price error.
        // We can either increase heartbeat or decrease lockPeriod(easier)
        ICellar _cellar = AaveV3SommelierBorrow(address(strategy)).cellar();
        vm.startPrank(_cellar.owner());
        // Set lock period to 600 seconds
        _cellar.setShareLockPeriod(600);
        vm.stopPrank();
    }
}

contract AaveV3SommelierBorrow_stETH_WETH_Ethereum_Test is AaveV3SommelierBorrow_Test {
    constructor() {
        MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS = 10;
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0003e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0004e18;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new AaveV3SommelierBorrowForStETH();
        deinitialize(address(strategy));
        AaveV3SommelierBorrowForStETH(address(strategy)).initialize(
            vaSTETH,
            address(swapperMock),
            aEthwstETH,
            WETH,
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            SOMMELIER_YIELD_ETH,
            wstETH,
            ""
        );

        // Both Aave and Master Oracle get prices from Chainlink
        swapperMock.updateMasterOracle(MASTER_ORACLE);
    }

    function deal(address token, address to, uint256 amount) internal override {
        IERC20 _stETH = AaveV3SommelierBorrowForStETH(address(strategy)).pool().token();
        if (token != address(_stETH)) {
            return super.deal(token, to, amount);
        }

        uint256 _prevBalance = _stETH.balanceOf(to);
        if (_prevBalance > amount) {
            // reduce balance by '_prevBalance - amount'.
            vm.prank(to);
            _stETH.transfer(address(0xDead), _prevBalance - amount);
        } else if (_prevBalance < amount) {
            uint256 _wrappedAmount = IWstETH(wstETH).getWstETHByStETH(amount - _prevBalance);
            super.deal(wstETH, to, _wrappedAmount);
            vm.prank(to);
            IWstETH(wstETH).unwrap(_wrappedAmount);
        }

        assertApproxEqAbs(_stETH.balanceOf(to), amount, 3, "deal for stETH didn't work");
    }

    function _getCollateralDeposit() internal view virtual override returns (uint256) {
        return
            AaveV3SommelierBorrowForStETH(address(strategy)).convertToStETH(
                IERC20(strategy.receiptToken()).balanceOf(address(strategy))
            );
    }

    function _increaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _pool = AaveV3SommelierBorrow(payable(address(strategy))).aavePoolAddressesProvider().getPool();

        _increaseTokenBalance(amount);

        vm.startPrank(address(strategy));
        uint256 supplyAmount = IWstETH(wstETH).wrap(amount);
        _pool.supply(address(strategy.collateralToken()), supplyAmount, address(strategy), 0);
        vm.stopPrank();
    }

    function _decreaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _pool = AaveV3SommelierBorrow(payable(address(strategy))).aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        uint256 withdrawAmount = AaveV3SommelierBorrowForStETH(address(strategy)).convertToWstETH(amount);
        _pool.withdraw(address(strategy.collateralToken()), withdrawAmount, address(strategy));
        uint256 withdrawn = IWstETH(wstETH).unwrap(strategy.collateralToken().balanceOf(address(strategy)));
        vm.stopPrank();

        _decreaseTokenBalance(withdrawn);
    }
}
