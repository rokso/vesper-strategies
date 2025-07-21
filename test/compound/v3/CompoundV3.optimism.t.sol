// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {CompoundV3} from "contracts/strategies/compound/v3/CompoundV3.sol";
import {CompoundV3_Test} from "test/compound/v3/CompoundV3.t.sol";
import {SWAPPER, vaETH, rewards, COMP, cWETHv3} from "test/helpers/Address.optimism.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract CompoundV3_ETH_Optimism_Test is CompoundV3_Test {
    function _setUp() internal override {
        super.createSelectFork("optimism");

        strategy = new CompoundV3();
        deinitialize(address(strategy));
        CompoundV3(address(strategy)).initialize(vaETH, SWAPPER, rewards, COMP, cWETHv3, "");
    }
}
