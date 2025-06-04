// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {VesperRewards} from "../../VesperRewards.sol";
import {CompoundV3Borrow} from "./CompoundV3Borrow.sol";

/// @title Deposit Collateral in Compound and earn interest by depositing borrowed token in a Vesper Pool.
contract CompoundV3VesperBorrow is CompoundV3Borrow {
    using SafeERC20 for IERC20;

    error InvalidGrowPool();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.CompoundV3VesperBorrow
    struct CompoundV3VesperBorrowStorage {
        IVesperPool _vPool;
    }

    bytes32 private constant CompoundV3VesperBorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.CompoundV3VesperBorrow")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getCompoundV3VesperBorrowStorage() private pure returns (CompoundV3VesperBorrowStorage storage $) {
        bytes32 _location = CompoundV3VesperBorrowStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        address compRewards_,
        address rewardToken_,
        address comet_,
        address borrowToken_,
        address vPool_,
        string memory name_
    ) external initializer {
        __CompoundV3Borrow_init(pool_, swapper_, compRewards_, rewardToken_, comet_, borrowToken_, name_);
        if (address(IVesperPool(vPool_).token()) != borrowToken()) revert InvalidGrowPool();
        _getCompoundV3VesperBorrowStorage()._vPool = IVesperPool(vPool_);
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return super.isReservedToken(token_) || token_ == address(vPool());
    }

    /// @notice Destination Grow Pool for borrowed Token
    function vPool() public view returns (IVesperPool) {
        return _getCompoundV3VesperBorrowStorage()._vPool;
    }

    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        IVesperPool _vPool = vPool();
        IERC20(borrowToken()).forceApprove(address(_vPool), amount_);
        VesperRewards._approveToken(_vPool, swapper(), amount_);
    }

    /// @dev Claim Compound and VSP rewards and convert to collateral token.
    function _claimAndSwapRewards() internal override {
        // Claim and swap Compound rewards
        super._claimAndSwapRewards();
        // Claim and swap rewards from Vesper
        VesperRewards._claimAndSwapRewards(vPool(), swapper(), address(collateralToken()));
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

    /// @dev Withdraw _shares proportional to collateral amount_ from vPool
    function _withdrawBorrowToken(uint256 amount_) internal override {
        IVesperPool _vPool = vPool();
        uint256 _pricePerShare = _vPool.pricePerShare();
        uint256 _shares = (amount_ * 1e18) / _pricePerShare;
        _shares = amount_ > ((_shares * _pricePerShare) / 1e18) ? _shares + 1 : _shares;
        uint256 _maxShares = _vPool.balanceOf(address(this));
        _shares = _shares > _maxShares ? _maxShares : _shares;
        if (_shares > 0) {
            _vPool.withdraw(_shares);
        }
    }
}
