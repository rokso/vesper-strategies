// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {AaveV3, ILendingPool} from "contracts/strategies/aave/v3/AaveV3.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, AAVE_V3_aUSDC, vaUSDC, AAVE_V3_POOL_ADDRESSES_PROVIDER} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract AaveV3_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    constructor() {
        MAX_DEPOSIT_SLIPPAGE_REL = 0.0000001e18;
    }

    function _setUp() internal override {
        vm.createSelectFork({urlOrAlias: "ethereum"});

        strategy = new AaveV3();
        deinitialize(address(strategy));
        AaveV3(address(strategy)).initialize(vaUSDC, SWAPPER, AAVE_V3_aUSDC, AAVE_V3_POOL_ADDRESSES_PROVIDER, "");
    }

    function _makeLoss(uint256 loss) internal override {
        ILendingPool _pool = AaveV3(address(strategy)).aavePoolAddressesProvider().getPool();

        vm.startPrank(address(strategy));
        _pool.withdraw(address(token()), loss, address(0xDead));
        vm.stopPrank();
    }

    function _makeProfit(uint256 profit) internal override {
        ILendingPool _pool = AaveV3(address(strategy)).aavePoolAddressesProvider().getPool();

        deal(address(token()), address(this), profit);
        token().approve(address(_pool), profit);
        _pool.supply(address(token()), profit, address(strategy), 0);
    }
}
