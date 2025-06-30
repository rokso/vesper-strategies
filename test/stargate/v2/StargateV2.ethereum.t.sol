// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "contracts/strategies/Strategy.sol";
import {StargateV2, IStargatePool, IStargateStaking} from "contracts/strategies/stargate/v2/StargateV2.sol";
import {Strategy_Withdraw_Test} from "test/Strategy.withdraw.t.sol";
import {Strategy_Rebalance_Test} from "test/Strategy.rebalance.t.sol";
import {SWAPPER, vaUSDC, STARGATE_V2_USDC_POOL, STARGATE_V2_STAKING} from "test/helpers/Address.ethereum.sol";
import {deinitialize} from "test/helpers/Functions.sol";

contract StargateV2_Ethereum_Test is Strategy_Withdraw_Test, Strategy_Rebalance_Test {
    function _setUp() internal override {
        super.createSelectFork("ethereum");

        strategy = new StargateV2();
        deinitialize(address(strategy));
        StargateV2(address(strategy)).initialize(
            vaUSDC,
            SWAPPER,
            IStargatePool(STARGATE_V2_USDC_POOL),
            IStargateStaking(STARGATE_V2_STAKING),
            ""
        );
    }

    function _decreaseCollateralDeposit(uint256 loss) internal override {
        IStargatePool _pool = StargateV2(address(strategy)).stargatePool();
        IERC20 _stargateLp = StargateV2(address(strategy)).stargateLp();

        vm.startPrank(address(strategy));
        StargateV2(address(strategy)).stargateStaking().withdraw(_stargateLp, loss);
        _pool.redeem(loss, address(0xDead));
        vm.stopPrank();
    }

    function _increaseCollateralDeposit(uint256 profit) internal override {
        IStargatePool _pool = StargateV2(address(strategy)).stargatePool();

        deal(address(token()), address(this), profit);
        token().approve(address(_pool), profit);
        _pool.deposit(address(strategy), profit);
    }
}
