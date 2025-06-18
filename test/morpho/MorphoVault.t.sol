// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {MorphoVault, IMetaMorpho} from "contracts/strategies/morpho/MorphoVault.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";

abstract contract MorphoVault_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    function _makeLoss(uint256 loss) internal override {
        IMetaMorpho _morpho = MorphoVault(address(strategy)).metaMorpho();

        vm.startPrank(address(strategy));
        _morpho.withdraw(loss, address(0xDead), address(strategy));
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        IMetaMorpho _morpho = MorphoVault(address(strategy)).metaMorpho();

        deal(address(token()), address(this), profit);
        token().approve(address(_morpho), profit);
        _morpho.deposit(profit, address(strategy));
    }
}
