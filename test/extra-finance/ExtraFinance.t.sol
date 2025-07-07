// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {ExtraFinance} from "contracts/strategies/extra-finance/ExtraFinance.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";

abstract contract ExtraFinance_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0000001e18;
        MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS = 1000;
    }

    function _decreaseCollateralDeposit(uint256 loss) internal override {
        ExtraFinance _strategy = ExtraFinance(payable(address(strategy)));

        uint256 _unstakeAmount = (loss * 1e18) / _strategy.lendingPool().exchangeRateOfReserve(_strategy.reserveId());

        vm.startPrank(address(strategy));
        _strategy.staking().withdraw(_unstakeAmount, address(0xDead));
        vm.stopPrank();
    }

    function _increaseCollateralDeposit(uint256 profit) internal override {
        ExtraFinance _strategy = ExtraFinance(payable(address(strategy)));

        deal(address(token()), address(this), profit);
        token().approve(address(_strategy.lendingPool()), profit);
        _strategy.lendingPool().deposit(_strategy.reserveId(), profit, address(strategy), 0);
    }
}
