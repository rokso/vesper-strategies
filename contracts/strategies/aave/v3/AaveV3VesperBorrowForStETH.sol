// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IWstETH} from "../../../interfaces/lido/IWstETH.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {VesperRewards} from "../../VesperRewards.sol";
import {AaveV3Borrow} from "./AaveV3Borrow.sol";

/// @title Deposit wstETH in Aave and earn yield by depositing borrowed token in a Vesper Pool.
contract AaveV3VesperBorrowForStETH is AaveV3Borrow {
    using SafeERC20 for IERC20;
    error InvalidGrowPool();
    /// @custom:storage-location erc7201:vesper.storage.Strategy.AaveV3VesperBorrow.stETH
    struct AaveV3VesperBorrowForStETHStorage {
        IWstETH _wstETH;
        IVesperPool _vPool;
    }

    bytes32 private constant AaveV3VesperBorrowForStETHStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.AaveV3VesperBorrow.stETH")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getAaveV3VesperBorrowForStETHStorage()
        internal
        pure
        returns (AaveV3VesperBorrowForStETHStorage storage $)
    {
        bytes32 _location = AaveV3VesperBorrowForStETHStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
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
        if (address(IVesperPool(vPool_).token()) != borrowToken_) revert InvalidGrowPool();
        AaveV3VesperBorrowForStETHStorage storage $ = _getAaveV3VesperBorrowForStETHStorage();
        $._wstETH = IWstETH(wstETH_);
        $._vPool = IVesperPool(vPool_);

        __AaveV3Borrow_init(pool_, swapper_, receiptToken_, borrowToken_, poolAddressesProvider_, name_);
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return super.isReservedToken(token_) || token_ == address(vPool());
    }

    function vPool() public view returns (IVesperPool) {
        return _getAaveV3VesperBorrowForStETHStorage()._vPool;
    }

    function wstETH() public view returns (IWstETH) {
        return _getAaveV3VesperBorrowForStETHStorage()._wstETH;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view override returns (uint256) {
        // receiptToken is aToken. aToken is 1:1 of wrapped collateral token
        return
            _calculateWrapped(collateralToken().balanceOf(address(this))) +
            wrappedCollateral().balanceOf(address(this)) +
            IERC20(receiptToken()).balanceOf(address(this));
    }

    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        IVesperPool _vPool = vPool();
        IERC20(borrowToken()).forceApprove(address(_vPool), amount_);
        VesperRewards._approveToken(_vPool, swapper(), amount_);
        collateralToken().forceApprove(address(wrappedCollateral()), amount_);
    }

    function _calculateUnwrapped(uint256 wrappedAmount_) internal view override returns (uint256) {
        return wstETH().getStETHByWstETH(wrappedAmount_);
    }

    function _calculateWrapped(uint256 unwrappedAmount_) internal view override returns (uint256) {
        return wstETH().getWstETHByStETH(unwrappedAmount_);
    }

    /// @dev Claim all rewards and convert to collateral.
    function _claimAndSwapRewards() internal override {
        // Claim rewards from Aave
        AaveV3Borrow._claimAndSwapRewards();
        VesperRewards._claimAndSwapRewards(vPool(), swapper(), address(wrappedCollateral()));
    }

    function _getWrappedToken(IERC20) internal view override returns (IERC20) {
        return IERC20(address(wstETH()));
    }

    /// @dev Deposit borrow tokens into the Vesper Pool
    function _depositBorrowToken(uint256 amount_) internal override {
        vPool().deposit(amount_);
    }

    /// @dev borrowToken balance here + borrowToken balance deposited in Vesper Pool
    function _getTotalBorrowBalance() internal view override returns (uint256) {
        IVesperPool _vPool = vPool();
        return
            IERC20(borrowToken()).balanceOf(address(this)) +
            ((_vPool.pricePerShare() * _vPool.balanceOf(address(this))) / 1e18);
    }

    /// @notice Withdraw _shares proportional to collateral amount_ from vPool
    function _withdrawBorrowToken(uint256 amount_) internal override {
        IVesperPool _vPool = vPool();
        if (amount_ > 0) {
            uint256 _pricePerShare = _vPool.pricePerShare();
            uint256 _shares = (amount_ * 1e18) / _pricePerShare;
            _shares = amount_ > ((_shares * _pricePerShare) / 1e18) ? _shares + 1 : _shares;
            _shares = Math.min(_shares, _vPool.balanceOf(address(this)));
            if (_shares > 0) {
                _vPool.withdraw(_shares);
            }
        }
    }

    function _unwrap(uint256 wrappedAmount_) internal override returns (uint256 _unwrappedAmount) {
        if (wrappedAmount_ > 0) {
            _unwrappedAmount = wstETH().unwrap(wrappedAmount_);
        }
    }

    function _wrap(uint256 unwrappedAmount_) internal override returns (uint256 _wrappedAmount) {
        if (unwrappedAmount_ > 0) {
            _wrappedAmount = wstETH().wrap(unwrappedAmount_);
        }
    }
}
