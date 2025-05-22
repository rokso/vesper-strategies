// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {ISwapperManagement} from "contracts/interfaces/swapper/ISwapperManagement.sol";
import {CompoundV3VesperBorrow} from "contracts/strategies/compound/v3/CompoundV3VesperBorrow.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaETH, WETH, cUSDCv3, USDC, vaUSDC, SWAPPER_UNIV3_ADAPTER} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract CompoundV3VesperBorrow_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_WITHDRAW_SLIPPAGE_REL = 0.0000000001e18;
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000000001e18;
    }

    function _setUp() internal override {
        vm.createSelectFork({urlOrAlias: "ethereum"});

        strategy = new CompoundV3VesperBorrow();
        deinitialize(address(strategy));
        CompoundV3VesperBorrow(payable(address(strategy))).initialize(vaETH, SWAPPER, cUSDCv3, USDC, vaUSDC, "");

        ISwapperManagement swapper = ISwapperManagement(SWAPPER);
        vm.prank(swapper.governor());
        swapper.setExactOutputRouting(WETH, USDC, SWAPPER_UNIV3_ADAPTER, abi.encodePacked(USDC, uint24(3000), WETH));
    }

    function _makeLoss(uint256 loss) internal override {
        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));

        vm.startPrank(address(strategy));
        _strategy.comet().withdraw(address(token()), loss);
        token().transfer(address(this), loss);
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        CompoundV3VesperBorrow _strategy = CompoundV3VesperBorrow(payable(address(strategy)));

        deal(address(token()), address(strategy), token().balanceOf(address(strategy)) + profit);
        vm.startPrank(address(strategy));
        _strategy.comet().supply(address(token()), profit);
        vm.stopPrank();
    }
}
