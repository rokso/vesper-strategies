// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IMasterOracle} from "contracts/interfaces/one-oracle/IMasterOracle.sol";

contract MasterOracleMock is IMasterOracle {
    mapping(address => uint256) public getPriceInUsd;

    error NoOraclePrice(address asset);

    function updatePrice(address _asset, uint256 _price) external {
        getPriceInUsd[_asset] = _price;
    }

    function quoteTokenToUsd(address _asset, uint256 _amount) public view override returns (uint256 _amountInUsd) {
        if (getPriceInUsd[_asset] == 0) revert NoOraclePrice(_asset);
        _amountInUsd = (_amount * getPriceInUsd[_asset]) / 10 ** IERC20Metadata(address(_asset)).decimals();
    }

    function quoteUsdToToken(address _asset, uint256 _amountInUsd) public view override returns (uint256 _amount) {
        if (getPriceInUsd[_asset] == 0) revert NoOraclePrice(_asset);
        _amount = (_amountInUsd * 10 ** IERC20Metadata(address(_asset)).decimals()) / getPriceInUsd[_asset];
    }

    function quote(
        address _assetIn,
        address _assetOut,
        uint256 _amountIn
    ) public view override returns (uint256 _amountOut) {
        uint256 _amountInUsd = quoteTokenToUsd(_assetIn, _amountIn);
        _amountOut = quoteUsdToToken(_assetOut, _amountInUsd);
    }
}
