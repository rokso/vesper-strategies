// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {FraxlendV1Borrow} from "./FraxlendV1Borrow.sol";

/// @title Deposit Collateral in Fraxlend and generate yield by depositing borrowed token into the Vesper Pool.
contract FraxlendV1VesperBorrow is FraxlendV1Borrow {
    using SafeERC20 for IERC20;

    error InvalidGrowPool();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.FraxlendV1VesperBorrow
    struct FraxlendV1VesperBorrowStorage {
        IVesperPool _vPool;
    }

    bytes32 private constant FraxlendV1VesperBorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.FraxlendV1VesperBorrow")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getFraxlendV1VesperBorrowStorage() internal pure returns (FraxlendV1VesperBorrowStorage storage $) {
        bytes32 _location = FraxlendV1VesperBorrowStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        address fraxlendPair_,
        address borrowToken_,
        address vPool_,
        string memory name_
    ) external initializer {
        __FraxlendV1Borrow_init(pool_, swapper_, fraxlendPair_, borrowToken_, name_);
        if (address(IVesperPool(vPool_).token()) != borrowToken()) revert InvalidGrowPool();
        _getFraxlendV1VesperBorrowStorage()._vPool = IVesperPool(vPool_);
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return super.isReservedToken(token_) || token_ == address(vPool());
    }

    /// @notice Destination Grow Pool for borrowed Token
    function vPool() public view returns (IVesperPool) {
        return _getFraxlendV1VesperBorrowStorage()._vPool;
    }

    /// @notice After borrowing borrow tokens, deposit tokens to Vesper Pool
    function _afterBorrow(uint256 amount_) internal override {
        vPool().deposit(amount_);
    }

    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        IVesperPool _vPool = vPool();
        IERC20(borrowToken()).forceApprove(address(_vPool), amount_);
    }

    function _getInvestedBorrowTokens() internal view override returns (uint256) {
        IVesperPool _vPool = vPool();
        return (_vPool.pricePerShare() * _vPool.balanceOf(address(this))) / 1e18;
    }

    /// @notice Withdraw _shares proportional to collateral _amount from vPool
    function _withdrawBorrowTokens(uint256 amount_) internal override {
        IVesperPool _vPool = vPool();
        uint256 _pricePerShare = _vPool.pricePerShare();
        uint256 _shares = (amount_ * 1e18) / _pricePerShare;
        _shares = amount_ > ((_shares * _pricePerShare) / 1e18) ? _shares + 1 : _shares;
        _shares = Math.min(_shares, _vPool.balanceOf(address(this)));
        if (_shares > 0) {
            _vPool.withdraw(_shares);
        }
    }
}
