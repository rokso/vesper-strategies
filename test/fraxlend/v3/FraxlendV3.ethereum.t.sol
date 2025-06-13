// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {FraxlendV3, IFraxlendPairV3} from "contracts/strategies/fraxlend/v3/FraxlendV3.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaFRAX, FRAXLEND_V3_sfrxETH_FRAX} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract FraxlendV3_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new FraxlendV3();
        deinitialize(address(strategy));
        FraxlendV3(address(strategy)).initialize(vaFRAX, SWAPPER, FRAXLEND_V3_sfrxETH_FRAX, "");
    }

    function _makeLoss(uint256 loss) internal override {
        IFraxlendPairV3 _pair = IFraxlendPairV3(address(FraxlendV3(address(strategy)).fraxlendPair()));

        vm.startPrank(address(strategy));
        _pair.withdraw(loss, address(0xDead), address(strategy));
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        IFraxlendPairV3 _pair = IFraxlendPairV3(address(FraxlendV3(address(strategy)).fraxlendPair()));
        deal(address(token()), address(this), profit);
        token().approve(address(_pair), profit);
        _pair.deposit(profit, address(strategy));
    }
}
