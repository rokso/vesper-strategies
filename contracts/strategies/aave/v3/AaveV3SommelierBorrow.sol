// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {ICellar} from "../../../interfaces/sommelier/ISommelier.sol";
import {SommelierBase} from "../../sommelier/SommelierBase.sol";
import {AaveV3Borrow} from "./AaveV3Borrow.sol";

/// @title Deposit Collateral in Aave and earn yield by depositing borrowed token in a Sommelier Vault.
contract AaveV3SommelierBorrow is AaveV3Borrow, SommelierBase {
    using SafeERC20 for IERC20;

    error InvalidSommelierVault();

    function initialize(
        address _pool,
        address _swapper,
        address _receiptToken,
        address _borrowToken,
        address _aaveAddressProvider,
        address _cellar,
        string memory _name
    ) public initializer {
        __AaveV3Borrow_init(_pool, _swapper, _receiptToken, _borrowToken, _aaveAddressProvider, _name);
        __Sommelier_init(_cellar);
        if (ICellar(_cellar).asset() != borrowToken()) revert InvalidSommelierVault();
    }

    /// @dev After borrowing Y, deposit to Sommelier vault
    function _afterBorrowY(uint256 _amount) internal virtual override {
        _depositInSommelier(_amount);
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 _amount) internal virtual override {
        super._approveToken(_amount);
        IERC20(borrowToken()).forceApprove(address(cellar()), _amount);
    }

    /// @dev Before repaying Y, withdraw it from Sommelier vault

    function _beforeRepayY(uint256 _amount) internal virtual override {
        _withdrawY(_amount);
    }

    /// @notice Withdraw _shares proportional to collateral _amount from vPool
    function _withdrawY(uint256 _amount) internal virtual override {
        _withdrawFromSommelier(_amount);
    }

    /// @dev borrowToken balance here + borrowToken balance deposited in Sommelier vault
    function _getInvestedBorrowBalance() internal view virtual override returns (uint256) {
        return IERC20(borrowToken()).balanceOf(address(this)) + _getAssetsInSommelier();
    }
}
