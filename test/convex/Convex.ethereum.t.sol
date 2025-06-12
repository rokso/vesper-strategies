// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {CurveBase, IConvex, Convex} from "contracts/strategies/convex/Convex.sol";
import {Convex_Test} from "./Convex.t.sol";
import {SWAPPER, vaUSDC, vaETH, CRV, CVX, CURVE_DEPOSIT_AND_STAKE, MASTER_ORACLE, WETH, CURVE_eUSD_USDC_POOL, CURVE_ynETHx_ETH_POOL, CONVEX_BOOSTER} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract Convex_Ethereum_eUSD_USDC_Test is Convex_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0095e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        CurveBase.CurveInitParams memory params = CurveBase.CurveInitParams({
            pool: vaUSDC,
            swapper: SWAPPER,
            curvePool: CURVE_eUSD_USDC_POOL,
            curvePoolZap: address(0),
            curveToken: CRV,
            depositAndStake: CURVE_DEPOSIT_AND_STAKE,
            useDynamicArray: true,
            slippage: 200,
            weth: WETH,
            masterOracle: MASTER_ORACLE,
            name: ""
        });

        strategy = new Convex();
        deinitialize(address(strategy));
        Convex(payable(address(strategy))).initialize(params, IConvex(CONVEX_BOOSTER), CVX, 369);
    }
}

contract Convex_Ethereum_ynETHx_ETH_Test is Convex_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0095e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        CurveBase.CurveInitParams memory params = CurveBase.CurveInitParams({
            pool: vaETH,
            swapper: SWAPPER,
            curvePool: CURVE_ynETHx_ETH_POOL,
            curvePoolZap: address(0),
            curveToken: CRV,
            depositAndStake: CURVE_DEPOSIT_AND_STAKE,
            useDynamicArray: true,
            slippage: 200,
            weth: WETH,
            masterOracle: MASTER_ORACLE,
            name: ""
        });

        strategy = new Convex();
        deinitialize(address(strategy));
        Convex(payable(address(strategy))).initialize(params, IConvex(CONVEX_BOOSTER), CVX, 418);
    }
}
