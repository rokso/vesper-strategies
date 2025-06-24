// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {AaveV3VesperBorrow} from "contracts/strategies/aave/v3/AaveV3VesperBorrow.sol";
import {AaveV3VesperBorrowForStETH} from "contracts/strategies/aave/v3/AaveV3VesperBorrowForStETH.sol";
import {IWstETH} from "contracts/interfaces/lido/IWstETH.sol";
import {AaveV3VesperBorrow_Test} from "test/aave/v3/AaveV3VesperBorrow.t.sol";
import {vaETH, vaSTETH, vaUSDC, aEthWETH, aEthwstETH, USDC, WETH, wstETH, AAVE_V3_POOL_ADDRESSES_PROVIDER} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract AaveV3VesperBorrow_ETH_USDC_Ethereum_Test is AaveV3VesperBorrow_Test {
    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new AaveV3VesperBorrow();
        deinitialize(address(strategy));
        AaveV3VesperBorrow(address(strategy)).initialize(
            vaETH,
            address(swapperMock),
            aEthWETH,
            USDC,
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            vaUSDC,
            ""
        );
        _oracleSetup(WETH, USDC);
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
            address(swapperMock),
            aEthwstETH,
            WETH,
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            vaETH,
            wstETH,
            ""
        );
        _oracleSetup(wstETH, WETH);
    }

    function deal(address token, address to, uint256 amount) internal override {
        IERC20 _stETH = AaveV3VesperBorrowForStETH(address(strategy)).stETH();
        if (token != address(_stETH)) {
            return super.deal(token, to, amount);
        }

        uint256 _prevBalance = _stETH.balanceOf(to);
        if (_prevBalance > amount) {
            // reduce balance by '_prevBalance - amount'.
            vm.prank(to);
            _stETH.transfer(address(0xDead), _prevBalance - amount);
        } else if (_prevBalance < amount) {
            uint256 _wrappedAmount = IWstETH(wstETH).getWstETHByStETH(amount);
            super.deal(wstETH, to, _wrappedAmount);
            vm.prank(to);
            IWstETH(wstETH).unwrap(_wrappedAmount);
        }
    }

    function _getWrappedAmount(uint256 unwrappedAmount) internal view override returns (uint256) {
        return IWstETH(wstETH).getWstETHByStETH(unwrappedAmount);
    }
}
