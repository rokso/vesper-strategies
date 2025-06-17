// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICellar} from "../../../interfaces/sommelier/ISommelier.sol";
import {SommelierBase} from "../../sommelier/SommelierBase.sol";
import {AaveV3Borrow} from "./AaveV3Borrow.sol";

/// @title Deposit Collateral in Aave and earn yield by depositing borrowed token in a Sommelier Vault.
contract AaveV3SommelierBorrow is AaveV3Borrow, SommelierBase {
    using SafeERC20 for IERC20;

    error InvalidSommelierVault();

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        address borrowToken_,
        address poolAddressesProvider_,
        address cellar_,
        string memory name_
    ) public initializer {
        __AaveV3Borrow_init(pool_, swapper_, receiptToken_, borrowToken_, poolAddressesProvider_, name_);
        __Sommelier_init(cellar_);
        if (ICellar(cellar_).asset() != borrowToken_) revert InvalidSommelierVault();
    }

    /// @dev Deposit borrow tokens into the Sommelier vault
    function _depositBorrowToken(uint256 amount_) internal override {
        _depositInSommelier(amount_);
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        IERC20(borrowToken()).forceApprove(address(cellar()), amount_);
    }

    /// @dev Before repaying borrow tokens, withdraw from Sommelier vault
    /// Withdraw _shares proportional to collateral amount_ from vPool
    function _withdrawBorrowToken(uint256 amount_) internal override {
        _withdrawFromSommelier(amount_);
    }

    /// @dev borrowToken balance here + borrowToken balance deposited in Sommelier vault
    function _getTotalBorrowBalance() internal view override returns (uint256) {
        return IERC20(borrowToken()).balanceOf(address(this)) + _getAssetsInSommelier();
    }
}
