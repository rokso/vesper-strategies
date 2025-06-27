// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {CompoundV3} from "contracts/strategies/compound/v3/CompoundV3.sol";
import {IComet} from "contracts/interfaces/compound/IComet.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";

abstract contract CompoundV3_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0000001e18;
    }

    function _decreaseCollateralDeposit(uint256 loss) internal override {
        IComet _comet = CompoundV3(address(strategy)).comet();

        vm.startPrank(address(strategy));
        _comet.withdrawTo(address(0xDead), address(token()), loss);
        vm.stopPrank();
    }

    function _increaseCollateralDeposit(uint256 profit) internal override {
        IComet _comet = CompoundV3(address(strategy)).comet();

        deal(address(token()), address(this), profit);
        token().approve(address(_comet), profit);
        _comet.supplyTo(address(strategy), address(token()), profit);
    }
}
