// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {Yearn, IYToken} from "contracts/strategies/yearn/Yearn.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaETH, YEARN_yvWETH} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract Yearn_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS = 1000;
        MAX_DEPOSIT_SLIPPAGE_REL = 0.000000000000001e18;
    }

    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new Yearn();
        deinitialize(address(strategy));
        Yearn(address(strategy)).initialize(vaETH, SWAPPER, YEARN_yvWETH, "");
    }

    function _makeLoss(uint256 loss) internal override {
        IYToken _yToken = Yearn(address(strategy)).yToken();
        uint256 _yTokenDecimals = 10 ** _yToken.decimals();
        uint256 _shares = (loss * _yTokenDecimals) / _yToken.pricePerShare();

        vm.startPrank(address(strategy));
        uint256 _before = token().balanceOf(address(strategy));
        _yToken.withdraw(_shares);
        uint256 _burn = token().balanceOf(address(strategy)) - _before;
        token().transfer(address(0xDead), _burn);
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        IYToken _yToken = Yearn(address(strategy)).yToken();

        vm.startPrank(address(strategy));
        deal(address(token()), address(strategy), token().balanceOf(address(strategy)) + profit);
        _yToken.deposit(profit);
        vm.stopPrank();
    }
}
