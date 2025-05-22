// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {IFraxlendPair} from "contracts/strategies/fraxlend/v1/FraxlendV1.sol";
import {FraxlendV1VesperBorrow} from "contracts/strategies/fraxlend/v1/FraxlendV1VesperBorrow.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaWBTC, vaFRAX, FRAX, FRAXLEND_V1_WBTC_FRAX} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract FraxlendV1VesperBorrow_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    function _setUp() internal override {
        vm.createSelectFork({urlOrAlias: "ethereum"});

        strategy = new FraxlendV1VesperBorrow();
        deinitialize(address(strategy));
        FraxlendV1VesperBorrow(address(strategy)).initialize(vaWBTC, SWAPPER, FRAXLEND_V1_WBTC_FRAX, FRAX, vaFRAX, "");
    }

    function _makeLoss(uint256 loss) internal override {
        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();

        vm.startPrank(address(strategy));
        _pair.removeCollateral(loss, address(0xDead));
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        IFraxlendPair _pair = FraxlendV1VesperBorrow(address(strategy)).fraxlendPair();
        deal(address(token()), address(this), profit);
        token().approve(address(_pair), profit);
        _pair.addCollateral(profit, address(strategy));
    }
}
