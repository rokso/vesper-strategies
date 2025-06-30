// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {MorphoVault} from "contracts/strategies/morpho/MorphoVault.sol";
import {MorphoVault_Test} from "test/morpho/MorphoVault.t.sol";
import {SWAPPER, vamsUSD, MORPHO_VAULT_METRONOME_msUSD} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract MorphoVault_Ethereum_Test is MorphoVault_Test {
    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vamsUSD, SWAPPER, MORPHO_VAULT_METRONOME_msUSD, "");
    }
}
