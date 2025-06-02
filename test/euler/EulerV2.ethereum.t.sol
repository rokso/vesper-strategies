// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {EulerV2, IEulerV2} from "contracts/strategies/euler/EulerV2.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaUSDC, EULER_V2_eUSDC2} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract EulerV2_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
        MAX_WITHDRAW_SLIPPAGE_REL = 0.000001e18;
    }

    function _setUp() internal override {
        vm.createSelectFork({urlOrAlias: "ethereum"});

        strategy = new EulerV2();
        deinitialize(address(strategy));
        EulerV2(address(strategy)).initialize(vaUSDC, SWAPPER, EULER_V2_eUSDC2, "");
    }

    function _makeLoss(uint256 loss) internal override {
        IEulerV2 _eToken = EulerV2(address(strategy)).euler();
        vm.startPrank(address(strategy));
        _eToken.withdraw(loss, address(0xDead), address(strategy));
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        IEulerV2 _eToken = EulerV2(address(strategy)).euler();
        deal(address(token()), address(this), profit);
        token().approve(address(_eToken), profit);
        _eToken.deposit(profit, address(strategy));
    }
}
