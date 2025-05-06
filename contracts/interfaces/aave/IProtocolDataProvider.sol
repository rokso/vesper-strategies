// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

interface IProtocolDataProvider {
    function getReserveTokensAddresses(
        address asset
    ) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress);

    function getReserveData(
        address asset
    )
        external
        view
        returns (
            uint256 availableLiquidity,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        );

    function getReserveConfigurationData(
        address asset
    )
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
}
