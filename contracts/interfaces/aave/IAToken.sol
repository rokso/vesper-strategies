// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIncentivesController} from "./IIncentivesController.sol";

interface IAToken is IERC20 {
    /**
     * @dev Returns the address of the incentives controller contract
     **/
    function getIncentivesController() external view returns (IIncentivesController);

    function mint(address user, uint256 amount, uint256 index) external returns (bool);

    function burn(address user, address receiverOfUnderlying, uint256 amount, uint256 index) external;

    //solhint-disable func-name-mixedcase
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
