// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.25;

interface IMetaRegistry {
    function get_gauge(address pool) external view returns (address);

    function get_lp_token(address pool) external view returns (address);

    function get_n_coins(address pool) external view returns (uint256);

    function get_n_underlying_coins(address pool) external view returns (uint256);

    function get_coins(address pool) external view returns (address[8] memory);

    function get_balances(address pool) external view returns (uint256[8] memory);

    function get_pool_from_lp_token(address token) external view returns (address);

    function get_underlying_coins(address pool) external view returns (address[8] memory);

    function get_underlying_balances(address pool) external view returns (uint256[8] memory);

    function is_meta(address pool) external view returns (bool);

    function is_registered(address pool) external view returns (bool);
}
