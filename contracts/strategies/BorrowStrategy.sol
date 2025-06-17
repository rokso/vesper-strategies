// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "./Strategy.sol";
import {IVesperPool} from "../interfaces/vesper/IVesperPool.sol";

// solhint-disable no-empty-blocks

/// @dev Common code and logic for borrow strategies
abstract contract BorrowStrategy is Strategy {
    error InvalidMaxBorrowLimit();
    error InvalidSlippage();
    error MaxShouldBeHigherThanMin();
    error NotEnoughTokensToRepay(uint256 repayAmount, uint256 borrowBalance);

    event UpdatedBorrowLimit(
        uint256 previousMinBorrowLimit,
        uint256 newMinBorrowLimit,
        uint256 previousMaxBorrowLimit,
        uint256 newMaxBorrowLimit
    );
    event UpdatedSlippage(uint256 previousSlippage, uint256 newSlippage);

    uint256 internal constant MAX_BPS = 10_000; //100%
    /// @custom:storage-location erc7201:vesper.storage.Strategy.Borrow
    struct BorrowStorage {
        address _borrowToken;
        uint256 _minBorrowLimit;
        uint256 _maxBorrowLimit;
        uint256 _slippage;
    }

    bytes32 private constant BorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.Borrow")) - 1)) & ~bytes32(uint256(0xff));

    function _getBorrowStorage() private pure returns (BorrowStorage storage $) {
        bytes32 _location = BorrowStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function __Borrow_init(
        address pool_,
        address swapper_,
        address receiptToken_,
        address borrowToken_,
        string memory name_
    ) internal onlyInitializing {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);
        if (borrowToken_ == address(0)) revert AddressIsNull();

        BorrowStorage storage $ = _getBorrowStorage();
        $._borrowToken = borrowToken_;

        $._minBorrowLimit = 7_000; // 70% of actual collateral factor of protocol
        $._maxBorrowLimit = 8_500; // 85% of actual collateral factor of protocol
        $._slippage = 300; // 3%
    }

    function borrowToken() public view returns (address) {
        return _getBorrowStorage()._borrowToken;
    }

    function isReservedToken(address token_) public view virtual override returns (bool) {
        return super.isReservedToken(token_) || token_ == borrowToken();
    }

    function maxBorrowLimit() public view returns (uint256) {
        return _getBorrowStorage()._maxBorrowLimit;
    }

    function minBorrowLimit() public view returns (uint256) {
        return _getBorrowStorage()._minBorrowLimit;
    }

    function slippage() public view returns (uint256) {
        return _getBorrowStorage()._slippage;
    }

    /// @dev It will make adjustment to maintain safe borrow position.
    /// 1. Check if position needs any adjustment.
    /// 2. Deposit collateral.
    /// 3. Repay borrow tokens.
    /// 4. Borrow more tokens.
    /// 5. Deposit borrow tokens in end protocol.
    function _adjustBorrowPosition(uint256 amount_, bool isDeposit_) internal {
        address _borrowToken = borrowToken();
        //
        // 1. Check if position needs to repay or borrow more
        //
        (uint256 _borrowAmount, uint256 _repayAmount) = _calculateBorrowPosition(amount_, isDeposit_);

        //
        // 2. Deposit collateral if any
        //
        if (isDeposit_ && amount_ > 0) {
            _depositCollateral(amount_);
        }

        //
        // 3. Repay borrow token to maintain safe position.
        //    Withdraw borrow tokens if needed.
        //
        uint256 _borrowBalanceHere;
        if (_repayAmount > 0) {
            _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
            if (_repayAmount > _borrowBalanceHere) {
                _withdrawBorrowToken(_repayAmount - _borrowBalanceHere);
                _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
                if (_repayAmount > _borrowBalanceHere) revert NotEnoughTokensToRepay(_repayAmount, _borrowBalanceHere);
            }
            _repay(_repayAmount);
        } else if (_borrowAmount > 0) {
            //
            // 4. Borrow tokens from protocol
            //
            _borrow(_borrowAmount);
        }

        //
        // 5. Deposit borrow tokens into the end protocol, if any.
        //
        // In ideal scenario we get borrow balance from _borrow() and deposit
        // should be called right after _borrow() inside `else if`.
        // If borrow balance is non zero and `if` conditions doesn't meet then
        // borrow balance will sit idle and not generate yield.
        _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
        if (_borrowBalanceHere > 0) {
            _depositBorrowToken(_borrowBalanceHere);
        }
    }

    /// @dev Borrow tokens from protocol
    function _borrow(uint256 borrowAmount_) internal virtual;

    /**
     * @notice Calculate borrow and repay amount based on current collateral and new deposit/withdraw amount.
     * @param amount_ amount to deposit or withdraw
     * @param isDeposit_ whether amount_ being deposited or withdrawn
     * @return _borrowAmount borrow more amount
     * @return _repayAmount repay amount to keep ltv within limits
     */
    function _calculateBorrowPosition(
        uint256 amount_,
        bool isDeposit_
    ) internal view virtual returns (uint256 _borrowAmount, uint256 _repayAmount);

    /// @dev Deposit borrowed token.
    /// It is usually called after borrowing tokens from first protocol.
    function _depositBorrowToken(uint256 amount_) internal virtual;

    /// @dev Deposit collateral in first protocol.
    function _depositCollateral(uint256 amount_) internal virtual;

    /// @dev Returns borrowed balance here and deposited into end protocol if any.
    function _getTotalBorrowBalance() internal view virtual returns (uint256) {
        return IERC20(borrowToken()).balanceOf(address(this));
    }

    function _getBorrowed() internal view virtual returns (uint256);

    function _getSupplied() internal view virtual returns (uint256);

    /**
     * @dev Get quote for token price in terms of other token.
     * @param tokenIn_ tokenIn
     * @param tokenOut_ tokenOut
     * @param amountIn_ amount of tokenIn_
     * @return amountOut of tokenOut_ for amountIn_ of tokenIn_
     */
    function _quote(address tokenIn_, address tokenOut_, uint256 amountIn_) internal view virtual returns (uint256);

    function _rebalanceBorrow() internal {
        uint256 _borrowed = _getBorrowed();
        uint256 _totalBorrowBalance = _getTotalBorrowBalance();
        // _borrow increases every block.
        if (_borrowed > _totalBorrowBalance) {
            // Loss making scenario. Convert collateral to borrowToken to repay loss
            _swapCollateralForBorrow(_borrowed - _totalBorrowBalance);
        } else {
            // excess borrow is profit
            _swapBorrowForCollateral(_totalBorrowBalance - _borrowed);
        }
    }

    function _rebalanceCollateral(
        IERC20 collateralToken_,
        uint256 collateralHere_,
        uint256 totalCollateral_
    ) internal returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        if (totalCollateral_ > _totalDebt) {
            _profit = totalCollateral_ - _totalDebt;
        } else {
            _loss = _totalDebt - totalCollateral_;
        }

        uint256 _profitAndExcessDebt = _profit + _excessDebt;
        if (collateralHere_ < _profitAndExcessDebt) {
            _withdrawHere(_profitAndExcessDebt - collateralHere_);
            collateralHere_ = collateralToken_.balanceOf(address(this));
        }
        // Set actual payback first and then profit. Make sure collateralHere_ >= _payback + profit.
        _payback = Math.min(collateralHere_, _excessDebt);
        _profit = collateralHere_ > _payback ? Math.min((collateralHere_ - _payback), _profit) : 0;
        // Report earning to pool
        _pool.reportEarning(_profit, _loss, _payback);
    }

    function _rebalance() internal virtual override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        //
        // 1. Rebalance borrow position
        //
        _rebalanceBorrow();

        //
        // 2. prepare collateral related data for rebalance
        //
        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _collateralHere + _getSupplied();

        //
        // 3. Rebalance collateral tokens and report earning to the Vesper pool
        //
        (_profit, _loss, _payback) = _rebalanceCollateral(_collateralToken, _collateralHere, _totalCollateral);

        //
        // 4. Adjust borrow position
        //
        _adjustBorrowPosition(_collateralToken.balanceOf(address(this)), true);
    }

    /// @dev Repay borrow tokens to first protocol
    function _repay(uint256 repayAmount_) internal virtual;

    /// @dev Swap excess borrow token for collateral token.
    function _swapBorrowForCollateral(uint256 excessBorrow_) private {
        if (excessBorrow_ > 0) {
            address _borrowToken = borrowToken();
            uint256 _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
            if (excessBorrow_ > _borrowBalanceHere) {
                _withdrawBorrowToken(excessBorrow_ - _borrowBalanceHere);
                _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
            }
            if (_borrowBalanceHere > 0) {
                address _collateralToken = address(collateralToken());
                // Swap minimum of excessBorrow_ and _borrowBalanceHere for collateral
                uint256 _amountIn = Math.min(excessBorrow_, _borrowBalanceHere);
                // Get quote for _amountIn of borrowToken to collateralToken
                uint256 _expectedAmountOut = _quote(_borrowToken, _collateralToken, _amountIn);
                // Take slippage into account
                uint256 _minAmountOut = (_expectedAmountOut * (MAX_BPS - slippage())) / MAX_BPS;
                // Swap borrow token for collateral
                swapper().swapExactInput(_borrowToken, _collateralToken, _amountIn, _minAmountOut, address(this));
            }
        }
    }

    /// @dev Swap collateral to borrowToken
    /// @param amountOut_ Expected output of this swap
    function _swapCollateralForBorrow(uint256 amountOut_) private {
        IERC20 _collateralToken = collateralToken();
        address _borrowToken = borrowToken();
        // Looking for _amountIn using fixed output amount
        // Get quote for _amountOut of borrowToken to collateralToken
        uint256 _expectedAmountIn = _quote(_borrowToken, address(_collateralToken), amountOut_);
        if (_expectedAmountIn > 0) {
            uint256 _maxAmountIn = (_expectedAmountIn * (MAX_BPS + slippage())) / MAX_BPS;
            uint256 _collateralHere = _collateralToken.balanceOf(address(this));
            // If we do not have enough collateral then withdraw from first protocol.
            if (_maxAmountIn > _collateralHere) {
                // Withdraw some collateral, so that we have enough collateral to get expected output
                _withdrawCollateral(_maxAmountIn - _collateralHere);
            }
            swapper().swapExactOutput(address(_collateralToken), _borrowToken, amountOut_, _maxAmountIn, address(this));
        }
    }

    function _withdrawBorrowToken(uint256 amount_) internal virtual;

    function _withdrawCollateral(uint256 amount_) internal virtual;

    /************************************************************************************************
     *                          Governor/admin/keeper function                                      *
     ***********************************************************************************************/
    /**
     * @notice Update upper and lower borrow limit.
     * Usually maxBorrowLimit < 100% of actual collateral factor of protocol.
     * @dev It is possible to set 0 as _minBorrowLimit to not borrow anything
     * @param minBorrowLimit_ It is % of actual collateral factor of protocol
     * @param maxBorrowLimit_ It is % of actual collateral factor of protocol
     */
    function updateBorrowLimit(uint256 minBorrowLimit_, uint256 maxBorrowLimit_) external onlyGovernor {
        if (maxBorrowLimit_ >= MAX_BPS) revert InvalidMaxBorrowLimit();

        // set _maxBorrowLimit and _minBorrowLimit to zero to disable borrow;
        if ((maxBorrowLimit_ != 0 || minBorrowLimit_ != 0) && maxBorrowLimit_ <= minBorrowLimit_)
            revert MaxShouldBeHigherThanMin();

        BorrowStorage storage $ = _getBorrowStorage();
        emit UpdatedBorrowLimit($._minBorrowLimit, minBorrowLimit_, $._maxBorrowLimit, maxBorrowLimit_);
        // To avoid liquidation due to price variations maxBorrowLimit is a
        // collateral factor that is less than actual collateral factor of protocol
        $._minBorrowLimit = minBorrowLimit_;
        $._maxBorrowLimit = maxBorrowLimit_;
    }

    function updateSlippage(uint256 newSlippage_) external onlyGovernor {
        if (newSlippage_ > MAX_BPS) revert InvalidSlippage();
        BorrowStorage storage $ = _getBorrowStorage();
        emit UpdatedSlippage($._slippage, newSlippage_);
        $._slippage = newSlippage_;
    }
}
