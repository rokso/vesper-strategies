// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {AaveV3Borrow} from "./AaveV3Borrow.sol";

/// @title Deposit Collateral in Aave and earn interest by depositing borrowed token in a Vesper Pool.
contract AaveV3VesperBorrow is AaveV3Borrow {
    using SafeERC20 for IERC20;

    error InvalidGrowPool();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.AaveV3VesperBorrow
    struct AaveV3VesperBorrowStorage {
        IVesperPool _vPool;
    }

    bytes32 private constant AaveV3VesperBorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.AaveV3VesperBorrow")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getAaveV3VesperBorrowStorage() private pure returns (AaveV3VesperBorrowStorage storage $) {
        bytes32 _location = AaveV3VesperBorrowStorageLocation;
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
        string memory name_
    ) public initializer {
        __AaveV3Borrow_init(pool_, swapper_, receiptToken_, borrowToken_, poolAddressesProvider_, name_);
        if (address(IVesperPool(vPool_).token()) != borrowToken()) revert InvalidGrowPool();
        _getAaveV3VesperBorrowStorage()._vPool = IVesperPool(vPool_);
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return super.isReservedToken(token_) || token_ == address(vPool());
    }

    function vPool() public view returns (IVesperPool) {
        return _getAaveV3VesperBorrowStorage()._vPool;
    }

    /// @dev Deposit borrow tokens into the Vesper Pool
    function _depositBorrowToken(uint256 amount_) internal override {
        vPool().deposit(amount_);
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        IVesperPool _vPool = vPool();
        IERC20(borrowToken()).forceApprove(address(_vPool), amount_);
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
}
