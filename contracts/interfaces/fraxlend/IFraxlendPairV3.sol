// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IFraxlendPairBase} from "./IFraxlendPairBase.sol";

// solhint-disable var-name-mixedcase
interface IFraxlendPairV3 is IFraxlendPairBase {
    struct ExchangeRateInfo {
        address oracle;
        uint32 maxOracleDeviation; // % of larger number, 1e5 precision
        uint184 lastTimestamp;
        uint256 lowExchangeRate;
        uint256 highExchangeRate;
    }

    /// @notice Stores information about the current exchange rate. Collateral:Asset ratio
    /// @dev Struct packed to save SLOADs. Amount of Collateral Token to buy 1e18 Asset Token
    function exchangeRateInfo() external view returns (ExchangeRateInfo memory);

    function getConstants()
        external
        pure
        returns (
            uint256 _LTV_PRECISION,
            uint256 _LIQ_PRECISION,
            uint256 _UTIL_PREC,
            uint256 _FEE_PRECISION,
            uint256 _EXCHANGE_PRECISION,
            uint256 _DEVIATION_PRECISION,
            uint256 _RATE_PRECISION,
            uint256 _MAX_PROTOCOL_FEE
        );

    /// @notice The ```toAssetAmount``` function converts a given number of shares to an asset amount
    /// @param _shares Shares of asset (fToken)
    /// @param _roundUp Whether to round up after division
    /// @param _previewInterest Whether to preview interest accrual before calculation
    /// @return _amount The amount of asset
    function toAssetAmount(uint256 _shares, bool _roundUp, bool _previewInterest) external view returns (uint256);

    /// @notice The ```toAssetShares``` function converts a given asset amount to a number of asset shares (fTokens)
    /// @param _amount The amount of asset
    /// @param _roundUp Whether to round up after division
    /// @param _previewInterest Whether to preview interest accrual before calculation
    /// @return _shares The number of shares (fTokens)
    function toAssetShares(uint256 _amount, bool _roundUp, bool _previewInterest) external view returns (uint256);

    function convertToAssets(uint256 _shares) external view returns (uint256 _assets);

    function convertToShares(uint256 _assets) external view returns (uint256 _shares);

    function pricePerShare() external view returns (uint256 _amount);

    function totalAssets() external view returns (uint256);

    function maxWithdraw(address _owner) external view returns (uint256 _maxAssets);

    /// @notice The ```withdraw``` function allows the caller to withdraw their Asset Tokens for a given amount of fTokens
    /// @param _amount The amount to withdraw
    /// @param _receiver The address to which the Asset Tokens will be transferred
    /// @param _owner The owner of the Asset Shares (fTokens)
    /// @return _sharesToBurn The number of shares (fTokens) that were burned
    function withdraw(uint256 _amount, address _receiver, address _owner) external returns (uint256 _sharesToBurn);
}
