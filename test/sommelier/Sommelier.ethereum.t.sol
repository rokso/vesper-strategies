// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {ICellar} from "contracts/strategies/sommelier/SommelierBase.sol";
import {Sommelier} from "contracts/strategies/sommelier/Sommelier.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaETH, SOMMELIER_YIELD_ETH} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract Sommelier_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0003e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0003e18;
    }

    function _setUp() internal override {
        vm.createSelectFork({urlOrAlias: "ethereum"});

        strategy = new Sommelier();
        deinitialize(address(strategy));
        Sommelier(address(strategy)).initialize(vaETH, SWAPPER, SOMMELIER_YIELD_ETH, "");
    }

    function _waitForUnlockTime() internal override {
        uint256 _unlockTime = Sommelier(address(strategy)).unlockTime();
        if (block.timestamp < _unlockTime) {
            vm.warp(_unlockTime);
        }
    }

    function _makeLoss(uint256 loss) internal override {
        ICellar _cellar = Sommelier(address(strategy)).cellar();
        _waitForUnlockTime();
        vm.prank(address(strategy));
        _cellar.withdraw(loss, address(0xDead), address(strategy));
    }

    function _makeProfit(uint256 profit) internal override {
        ICellar _cellar = Sommelier(address(strategy)).cellar();
        deal(address(token()), address(strategy), token().balanceOf(address(strategy)) + profit);
        vm.prank(address(strategy));
        _cellar.deposit(profit, address(strategy));
    }
}
