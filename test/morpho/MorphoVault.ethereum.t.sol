// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {MorphoVault} from "contracts/strategies/morpho/MorphoVault.sol";
import {MorphoVault_Test} from "test/morpho/MorphoVault.t.sol";
import {SWAPPER, vamsUSD, vaUSDC, MORPHO_VAULT_METRONOME_msUSD, MEV_Capital_USDC} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract MorphoVault_Metronome_msUSD_Ethereum_Test is MorphoVault_Test {
    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vamsUSD, SWAPPER, MORPHO_VAULT_METRONOME_msUSD, "");
    }
}

contract MorphoVault_MEV_Capital_USDC_Ethereum_Test is MorphoVault_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vaUSDC, SWAPPER, MEV_Capital_USDC, "");
    }
}
