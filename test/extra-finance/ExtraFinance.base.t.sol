// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {ExtraFinance, ILendingPool} from "contracts/strategies/extra-finance/ExtraFinance.sol";
import {ExtraFinance_Test} from "test/extra-finance/ExtraFinance.t.sol";

import {SWAPPER, vaETH, vaUSDC, EXTRA_FINANCE_LENDING_POOL} from "test/helpers/Address.base.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract ExtraFinance_ETH_1_Base_Test is ExtraFinance_Test {
    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new ExtraFinance();
        deinitialize(address(strategy));
        ExtraFinance(payable(address(strategy))).initialize(
            vaETH,
            SWAPPER,
            ILendingPool(EXTRA_FINANCE_LENDING_POOL),
            1,
            ""
        );
    }
}

contract ExtraFinance_USDC_1_Base_Test is ExtraFinance_Test {
    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new ExtraFinance();
        deinitialize(address(strategy));
        ExtraFinance(payable(address(strategy))).initialize(
            vaUSDC,
            SWAPPER,
            ILendingPool(EXTRA_FINANCE_LENDING_POOL),
            24,
            ""
        );
    }
}

contract ExtraFinance_USDC_2_Base_Test is ExtraFinance_Test {
    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new ExtraFinance();
        deinitialize(address(strategy));
        ExtraFinance(payable(address(strategy))).initialize(
            vaUSDC,
            SWAPPER,
            ILendingPool(EXTRA_FINANCE_LENDING_POOL),
            25,
            ""
        );
    }
}
