// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {AaveV3VesperBorrow} from "contracts/strategies/aave/v3/AaveV3VesperBorrow.sol";
import {AaveV3VesperBorrowForStETH} from "contracts/strategies/aave/v3/AaveV3VesperBorrowForStETH.sol";
import {ILendingPool} from "contracts/interfaces/aave/ILendingPool.sol";
import {IWstETH} from "contracts/interfaces/lido/IWstETH.sol";
import {AaveV3VesperBorrow_Test} from "test/aave/v3/AaveV3VesperBorrow.t.sol";
import {vaETH, SWAPPER, MASTER_ORACLE, vaSTETH, vaUSDC, aEthWETH, aEthwstETH, USDC, WETH, stETH, wstETH, AAVE_V3_POOL_ADDRESSES_PROVIDER} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract AaveV3VesperBorrow_ETH_USDC_Ethereum_Test is AaveV3VesperBorrow_Test {
    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new AaveV3VesperBorrow();
        deinitialize(address(strategy));
        AaveV3VesperBorrow(address(strategy)).initialize(
            vaETH,
            address(swapperMock), // TODO: Add missing routings or change tokens
            aEthWETH,
            USDC,
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            vaUSDC,
            ""
        );

        // Both Aave and Master Oracle get prices from Chainlink
        swapperMock.updateMasterOracle(MASTER_ORACLE);
    }
}

contract AaveV3VesperBorrow_stETH_WETH_Ethereum_Test is AaveV3VesperBorrow_Test {
    constructor() {
        MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS = 10;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new AaveV3VesperBorrowForStETH();
        deinitialize(address(strategy));
        AaveV3VesperBorrowForStETH(address(strategy)).initialize(
            vaSTETH,
            SWAPPER,
            aEthwstETH,
            WETH,
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            vaETH,
            wstETH,
            ""
        );
    }

    function deal(address token, address to, uint256 amount) internal override {
        IERC20 _stETH = AaveV3VesperBorrowForStETH(address(strategy)).pool().token();
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
            AaveV3VesperBorrowForStETH(address(strategy)).convertToStETH(
                IERC20(strategy.receiptToken()).balanceOf(address(strategy))
            );
    }

    function _increaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _pool = AaveV3VesperBorrow(payable(address(strategy))).aavePoolAddressesProvider().getPool();

        _increaseTokenBalance(amount);

        vm.startPrank(address(strategy));
        uint256 supplyAmount = IWstETH(wstETH).wrap(amount);
        _pool.supply(address(strategy.collateralToken()), supplyAmount, address(strategy), 0);
        vm.stopPrank();
    }

    function _decreaseCollateralDeposit(uint256 amount) internal override {
        require(amount > 0, "amount should be greater than 0");

        ILendingPool _pool = AaveV3VesperBorrow(payable(address(strategy))).aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        uint256 withdrawAmount = AaveV3VesperBorrowForStETH(address(strategy)).convertToWstETH(amount);
        _pool.withdraw(address(strategy.collateralToken()), withdrawAmount, address(strategy));
        uint256 withdrawn = IWstETH(wstETH).unwrap(strategy.collateralToken().balanceOf(address(strategy)));
        vm.stopPrank();

        _decreaseTokenBalance(withdrawn);
    }
}
