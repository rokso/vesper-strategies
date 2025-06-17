// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWstETH} from "../../../interfaces/lido/IWstETH.sol";
import {ICellar} from "../../../interfaces/sommelier/ISommelier.sol";
import {SommelierBase} from "../../sommelier/SommelierBase.sol";
import {AaveV3Borrow} from "./AaveV3Borrow.sol";

/// @title Deposit wstETH in Aave and earn yield by depositing borrowed token in a Sommelier vault.
contract AaveV3SommelierBorrowForStETH is AaveV3Borrow, SommelierBase {
    using SafeERC20 for IERC20;

    error InvalidSommelierVault();

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

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        address borrowToken_,
        address poolAddressesProvider_,
        address cellar_,
        address wstETH_,
        string memory name_
    ) external initializer {
        // Set wstETH before calling init on parent contract
        if (wstETH_ == address(0)) revert AddressIsNull();
        _getAaveV3SommelierBorrowForStETHStorage()._wstETH = IWstETH(wstETH_);

        __AaveV3Borrow_init(pool_, swapper_, receiptToken_, borrowToken_, poolAddressesProvider_, name_);
        __Sommelier_init(cellar_);
        if (ICellar(cellar_).asset() != borrowToken_) revert InvalidSommelierVault();
    }

    function collateralToken() public view override returns (IERC20) {
        return IERC20(address(_wstETH()));
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return super.isReservedToken(token_) || token_ == address(cellar());
    }

    function stETH() public view returns (IERC20) {
        return pool().token();
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view override returns (uint256) {
        // receiptToken is aToken. aToken is 1:1 of wstETH
        return
            _calculateWrapped(stETH().balanceOf(address(this))) +
            collateralToken().balanceOf(address(this)) +
            IERC20(receiptToken()).balanceOf(address(this));
    }

    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        IERC20(borrowToken()).forceApprove(address(cellar()), amount_);
        stETH().forceApprove(address(collateralToken()), amount_);
    }

    /// @dev Deposit borrow tokens into the Sommelier vault
    function _depositBorrowToken(uint256 amount_) internal override {
        _depositInSommelier(amount_);
    }

    /// @dev borrowToken balance here + borrowToken balance deposited in Sommelier vault
    function _getTotalBorrowBalance() internal view override returns (uint256) {
        return IERC20(borrowToken()).balanceOf(address(this)) + _getAssetsInSommelier();
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        //
        // 1. Rebalance borrow position
        //
        _rebalanceBorrow();

        //
        // 2. prepare pool collateral related data for rebalance
        // Note: Pool supports stETH so prepare data in terms of stETH.
        //
        IERC20 _collateralToken = collateralToken();
        _unwrap(_collateralToken.balanceOf(address(this)));

        IERC20 _stETH = stETH();
        uint256 _stEthHere = _stETH.balanceOf(address(this));
        uint256 _totalSteth = _stEthHere + _calculateUnwrapped(_getSupplied());

        //
        // 3. Rebalance collateral tokens and report earning to the Vesper pool
        //
        (_profit, _loss, _payback) = _rebalanceCollateral(_stETH, _stEthHere, _totalSteth);

        //
        // 4. wrap stETH received from the Vesper pool
        //
        _wrap(_stETH.balanceOf(address(this)));

        //
        // 5. Adjust borrow position
        //
        _adjustBorrowPosition(_collateralToken.balanceOf(address(this)), true);
    }

    /// @dev Before repaying borrow tokens, withdraw from Sommelier vault
    /// Withdraw _shares proportional to collateral amount_ from vPool
    function _withdrawBorrowToken(uint256 amount_) internal override {
        _withdrawFromSommelier(amount_);
    }

    function _withdrawHere(uint256 amount_) internal override {
        //
        // Note:
        // In this strategy, pool collateral is stETH and strategy collateral is wstETH.
        // When _withdrawHere is called 'amount_' is always in pool collateral i.e. stETH.
        // 1. calculate wrapped of amount_ to call parent _withdrawHere().
        // 2. Call parents withdrawHere
        //
        super._withdrawHere(_calculateWrapped(amount_));

        //
        // 3. unwrap withdrawn wstETH.
        // Note: There is no issue if we convert all wstETH to stETH.
        _unwrap(collateralToken().balanceOf(address(this)));
    }

    /************************************************************************************************
     *                                 wstETH helper functions                                      *
     ***********************************************************************************************/
    function _wstETH() internal view returns (IWstETH) {
        return _getAaveV3SommelierBorrowForStETHStorage()._wstETH;
    }

    function _calculateUnwrapped(uint256 wrappedAmount_) internal view returns (uint256) {
        return _wstETH().getStETHByWstETH(wrappedAmount_);
    }

    function _calculateWrapped(uint256 unwrappedAmount_) internal view returns (uint256) {
        return _wstETH().getWstETHByStETH(unwrappedAmount_);
    }

    function _unwrap(uint256 wrappedAmount_) internal returns (uint256 _unwrappedAmount) {
        if (wrappedAmount_ > 0) {
            _unwrappedAmount = _wstETH().unwrap(wrappedAmount_);
        }
    }

    function _wrap(uint256 unwrappedAmount_) internal returns (uint256 _wrappedAmount) {
        if (unwrappedAmount_ > 0) {
            _wrappedAmount = _wstETH().wrap(unwrappedAmount_);
        }
    }
}
