// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.25;

interface IDepositAndStake {
    /**
     * @notice Deposit coins into Curve pool and stake LP tokens into a Curve gauge.
     * @param deposit Address of the deposit contract. It can be Curve pool or zap.
     * @param lpToken Address of the LP token.
     * @param gauge Address of the gauge.
     * @param nCoins Number of coins in the pool.
     * @param coins Array of coin addresses.
     * @param amounts Array of amounts to deposit for each coin.
     * @param minMintAmount Minimum amount of LP tokens to mint.
     * @param useUnderlying Boolean indicating whether to use underlying tokens.
     * @param useDynArray Boolean indicating whether to use dynamic arrays.
     * @param pool It can be null. If zap contract is used as 'deposit' then it will be address of the curve pool.
     */
    function deposit_and_stake(
        address deposit,
        address lpToken,
        address gauge,
        uint256 nCoins,
        address[] calldata coins,
        uint256[] calldata amounts,
        uint256 minMintAmount,
        bool useUnderlying,
        bool useDynArray,
        address pool
    ) external payable;
}

interface IWithdraw {
    // Remove liquidity one coin
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external;

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 _min_amount,
        bool _use_underlying
    ) external;

    function remove_liquidity_one_coin(address _pool, uint256 _burn_amount, int128 i, uint256 _min_amount) external;

    // Remove liquidity in all tokens
    // For plain Curve pools
    function remove_liquidity(uint256 _amount, uint256[2] memory _min_amounts) external;

    function remove_liquidity(uint256 _amount, uint256[3] memory _min_amounts) external;

    function remove_liquidity(uint256 _amount, uint256[4] memory _min_amounts) external;

    // For LendingToken Curve pools where use_underlying flag exists
    function remove_liquidity(uint256 amount, uint256[2] calldata min_amounts, bool use_underlying) external;

    function remove_liquidity(uint256 amount, uint256[3] calldata min_amounts, bool use_underlying) external;

    function remove_liquidity(uint256 amount, uint256[4] calldata min_amounts, bool use_underlying) external;

    // For Curve pools where Zap contract is used i.e. Meta pools
    function remove_liquidity(address _pool, uint256 _burn_amount, uint256[2] memory _min_amounts) external;

    function remove_liquidity(address _pool, uint256 _burn_amount, uint256[3] memory _min_amounts) external;

    function remove_liquidity(address _pool, uint256 _burn_amount, uint256[4] memory _min_amounts) external;

    // For Curve pools with dynamic array
    function remove_liquidity(uint256 _amount, uint256[] memory _min_amounts) external;

    function remove_liquidity(address _pool, uint256 _burn_amount, uint256[] memory _min_amounts) external;
}
