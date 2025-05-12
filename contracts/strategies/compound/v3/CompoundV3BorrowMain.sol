// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {CompoundV3Borrow} from "./CompoundV3Borrow.sol";

/// @title This strategy will deposit collateral token in Compound V3 and based on position it will
/// borrow based token. Supply X borrow Y and keep borrowed amount here.
/// It does not handle ETH as collateral
contract CompoundV3BorrowMain is CompoundV3Borrow {
    function initialize(
        address pool_,
        address swapper_,
        address comet_,
        address borrowToken_,
        string memory name_
    ) public initializer {
        __CompoundV3Borrow_init(pool_, swapper_, comet_, borrowToken_, name_);
    }
}
