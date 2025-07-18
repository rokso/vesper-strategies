// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {ExtraFinance, ILendingPool} from "contracts/strategies/extra-finance/ExtraFinance.sol";
import {ExtraFinance_Test} from "test/extra-finance/ExtraFinance.t.sol";

import {SWAPPER, vaOP, LendingPool} from "test/helpers/Address.optimism.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract ExtraFinance_Pool1_OP_Optimism_Test is ExtraFinance_Test {
    function _setUp() internal override {
        super.createSelectFork("optimism");

        strategy = new ExtraFinance();
        deinitialize(address(strategy));
        ExtraFinance(payable(address(strategy))).initialize(vaOP, SWAPPER, ILendingPool(LendingPool), 4, "");
    }
}
