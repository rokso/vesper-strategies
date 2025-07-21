// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {MorphoVault} from "contracts/strategies/morpho/MorphoVault.sol";
import {MorphoVault_Test} from "test/morpho/MorphoVault.t.sol";
import {SWAPPER, vaETH, vamsETH, vaUSDC, Extrafi_XLend_WETH, Extrafi_XLend_USDC, Metronome_msETH, Moonwell_Flagship_ETH, Moonwell_Flagship_USDC} from "test/helpers/Address.base.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract MorphoVault_XLend_WETH_Base_Test is MorphoVault_Test {
    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vaETH, SWAPPER, Extrafi_XLend_WETH, "");
    }
}

contract MorphoVault_XLend_USDC_Base_Test is MorphoVault_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vaUSDC, SWAPPER, Extrafi_XLend_USDC, "");
    }
}

contract MorphoVault_Moonwell_ETH_Base_Test is MorphoVault_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vaETH, SWAPPER, Moonwell_Flagship_ETH, "");
    }
}

contract MorphoVault_Moonwell_USDC_Base_Test is MorphoVault_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vaUSDC, SWAPPER, Moonwell_Flagship_USDC, "");
    }
}

contract MorphoVault_Metronome_msETH_Base_Test is MorphoVault_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new MorphoVault();
        deinitialize(address(strategy));
        MorphoVault(address(strategy)).initialize(vamsETH, SWAPPER, Metronome_msETH, "");
    }
}
