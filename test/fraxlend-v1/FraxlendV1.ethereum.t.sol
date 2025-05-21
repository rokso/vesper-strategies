// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {FraxlendV1, IFraxlendPair} from "contracts/strategies/fraxlend/FraxlendV1.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaFRAX, FRAXLEND_V1_sfrxETH_FRAX} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract FraxlendV1_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        // MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
    }

    function _setUp() internal override {
        vm.createSelectFork({urlOrAlias: "ethereum"});

        strategy = new FraxlendV1();
        deinitialize(address(strategy));
        FraxlendV1(address(strategy)).initialize(vaFRAX, SWAPPER, FRAXLEND_V1_sfrxETH_FRAX, "");
    }

    function _makeLoss(uint256 loss) internal override {
        IFraxlendPair _pair = FraxlendV1(address(strategy)).fraxlendPair();

        uint256 _shares = _pair.toAssetShares(loss, false);

        vm.startPrank(address(strategy));
        _pair.redeem(_shares, address(0xDead), address(strategy));
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        IFraxlendPair _pair = FraxlendV1(address(strategy)).fraxlendPair();
        deal(address(token()), address(this), profit);
        token().approve(address(_pair), profit);
        _pair.deposit(profit, address(strategy));
    }
}
