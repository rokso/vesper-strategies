// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {CurveBase} from "./CurveBase.sol";

/// @title This strategy will deposit collateral token in a Curve Pool and earn interest.
// solhint-disable no-empty-blocks
contract Curve is CurveBase {
    function initialize(CurveInitParams memory params_) external initializer {
        __CurveBase_init(params_);
    }
}
