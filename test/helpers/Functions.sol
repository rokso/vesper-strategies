// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdConstants} from "forge-std/StdConstants.sol";
import {INITIALIZABLE_STORAGE} from "./Constants.sol";

function deinitialize(address strategy) {
    Vm vm = Vm(StdConstants.VM);
    vm.store(strategy, INITIALIZABLE_STORAGE, bytes32(uint256(0)));
}
