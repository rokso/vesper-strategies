// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWstETH} from "../../../interfaces/lido/IWstETH.sol";
import {AaveV3SommelierBorrow} from "./AaveV3SommelierBorrow.sol";

/// @title Deposit wstETH in Aave and earn yield by depositing borrowed token in a Sommelier vault.
contract AaveV3SommelierBorrowForStETH is AaveV3SommelierBorrow {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:vesper.storage.Strategy.AaveV3SommelierBorrow.stETH
    struct AaveV3SommelierBorrowForStETHStorage {
        IWstETH _wstETH;
    }

    bytes32 private constant AaveV3SommelierBorrowForStETHStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.AaveV3SommelierBorrow.stETH")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getAaveV3SommelierBorrowForStETHStorage()
        internal
        pure
        returns (AaveV3SommelierBorrowForStETHStorage storage $)
    {
        bytes32 _location = AaveV3SommelierBorrowForStETHStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function AaveV3SommelierBorrowForStETH_initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        address borrowToken_,
        address poolAddressesProvider_,
        address vPool_,
        address wstETH_,
        string memory name_
    ) external initializer {
        // Set wstETH before calling init on parent contract
        if (wstETH_ == address(0)) revert AddressIsNull();
        _getAaveV3SommelierBorrowForStETHStorage()._wstETH = IWstETH(wstETH_);

        super.initialize(pool_, swapper_, receiptToken_, borrowToken_, poolAddressesProvider_, vPool_, name_);
    }

    function wstETH() public view returns (IWstETH) {
        return _getAaveV3SommelierBorrowForStETHStorage()._wstETH;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view  override returns (uint256) {
        // receiptToken is aToken. aToken is 1:1 of collateral token
        return
            IERC20(receiptToken()).balanceOf(address(this)) +
            wrappedCollateral().balanceOf(address(this)) +
            _calculateWrapped(collateralToken().balanceOf(address(this)));
    }

    function _approveToken(uint256 amount_) internal  override {
        super._approveToken(amount_);
        collateralToken().forceApprove(address(wrappedCollateral()), amount_);
    }

    function _calculateUnwrapped(uint256 wrappedAmount_) internal view override returns (uint256) {
        return wstETH().getStETHByWstETH(wrappedAmount_);
    }

    function _calculateWrapped(uint256 unwrappedAmount_) internal view override returns (uint256) {
        return wstETH().getWstETHByStETH(unwrappedAmount_);
    }

    function _getCollateralHere() internal  override returns (uint256) {
        uint256 _wrapped = wrappedCollateral().balanceOf(address(this));
        if (_wrapped > 0) {
            _unwrap(_wrapped);
        }
        // Return unwrapped balance
        return collateralToken().balanceOf(address(this));
    }

    function _getWrappedToken(IERC20) internal view override returns (IERC20) {
        return IERC20(address(wstETH()));
    }

    function _unwrap(uint256 wrappedAmount_) internal override returns (uint256) {
        return wstETH().unwrap(wrappedAmount_);
    }

    function _wrap(uint256 unwrappedAmount_) internal override returns (uint256) {
        return wstETH().wrap(unwrappedAmount_);
    }
}
