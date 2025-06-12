// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {ExtraFinance, ILendingPool} from "contracts/strategies/extra-finance/ExtraFinance.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaETH, EXTRA_FINANCE_LENDING_POOL} from "test/helpers/Address.base.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract ExtraFinance_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0000001e18;
        MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS = 1000;
    }

    function _setUp() internal override {
        super.createSelectFork("base");

        strategy = new ExtraFinance();
        deinitialize(address(strategy));
        ExtraFinance(payable(address(strategy))).initialize(
            vaETH,
            SWAPPER,
            ILendingPool(EXTRA_FINANCE_LENDING_POOL),
            1,
            ""
        );
    }

    function _makeLoss(uint256 loss) internal override {
        ExtraFinance _strategy = ExtraFinance(payable(address(strategy)));

        uint256 _unstakeAmount = (loss * 1e18) / _strategy.lendingPool().exchangeRateOfReserve(_strategy.reserveId());

        vm.startPrank(address(strategy));
        _strategy.staking().withdraw(_unstakeAmount, address(0xDead));
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        ExtraFinance _strategy = ExtraFinance(payable(address(strategy)));

        deal(address(token()), address(this), profit);
        token().approve(address(_strategy.lendingPool()), profit);
        _strategy.lendingPool().deposit(_strategy.reserveId(), profit, address(strategy), 0);
    }
}
