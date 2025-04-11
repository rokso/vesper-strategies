// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {ILendingPool} from "./ILendingPool.sol";
import {IAaveOracle} from "./IAaveOracle.sol";
import {IProtocolDataProvider} from "./IProtocolDataProvider.sol";

interface IPoolAddressesProvider {
    function getPool() external view returns (ILendingPool);

    function getPoolDataProvider() external view returns (IProtocolDataProvider);

    function getPriceOracle() external view returns (IAaveOracle);
}
