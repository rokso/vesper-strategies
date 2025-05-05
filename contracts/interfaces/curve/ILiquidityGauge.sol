// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILiquidityGauge {
    function lp_token() external view returns (address);

    function deposit(uint256 _value) external;

    function withdraw(uint256 _value) external;
}

interface ILiquidityGaugeReward {
    function rewarded_token() external view returns (address);
}

interface ILiquidityGaugeV2 is IERC20, ILiquidityGauge {
    function claim_rewards() external;

    function reward_count() external view returns (uint256);

    function reward_tokens(uint256 _i) external view returns (address);

    function set_approve_deposit(address addr, bool can_deposit) external;
}

/* solhint-enable */
