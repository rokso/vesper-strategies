// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../../Strategy.sol";
import {AggregatorV3Interface} from "../../../interfaces/chainlink/AggregatorV3Interface.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {IFraxlendPair} from "../../../interfaces/fraxlend/IFraxlendPair.sol";

// solhint-disable var-name-mixedcase

/// @title This strategy will deposit collateral token in Fraxlend and based on position it will
/// borrow Frax.
abstract contract FraxlendV1Borrow is Strategy {
    using SafeERC20 for IERC20;

    error CollateralMismatch();
    error InvalidMaxBorrowLimit();
    error InvalidSlippage();
    error MaxShouldBeHigherThanMin();
    error PriceError();

    uint256 private constant MAX_BPS = 10_000; //100%

    event UpdatedBorrowLimit(
        uint256 previousMinBorrowLimit,
        uint256 newMinBorrowLimit,
        uint256 previousMaxBorrowLimit,
        uint256 newMaxBorrowLimit
    );

    event UpdatedSlippage(uint256 previousSlippage, uint256 newSlippage);

    /// @custom:storage-location erc7201:vesper.storage.Strategy.FraxlendV1Borrow
    struct FraxlendV1BorrowStorage {
        address _borrowToken;
        uint256 _minBorrowLimit;
        uint256 _maxBorrowLimit;
        uint256 _slippage;
        uint256 _exchangePrecision;
        uint256 _ltvPrecision;
        uint256 _maxLtv;
    }

    bytes32 private constant FraxlendV1BorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.FraxlendV1Borrow")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getFraxlendV1BorrowStorage() private pure returns (FraxlendV1BorrowStorage storage $) {
        bytes32 _location = FraxlendV1BorrowStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function __FraxlendV1Borrow_init(
        address pool_,
        address swapper_,
        address fraxlendPair_,
        address borrowToken_,
        string memory name_
    ) internal onlyInitializing {
        __Strategy_init(pool_, swapper_, fraxlendPair_, name_);

        if (borrowToken_ == address(0)) revert AddressIsNull();

        // This strategy will deposit collateral, collateralContract(), and borrow FRAX.
        if (IFraxlendPair(fraxlendPair_).collateralContract() != address(collateralToken()))
            revert CollateralMismatch();

        FraxlendV1BorrowStorage storage $ = _getFraxlendV1BorrowStorage();
        $._borrowToken = borrowToken_;
        $._minBorrowLimit = 7_000; // 70% of actual collateral factor of protocol
        $._maxBorrowLimit = 8_500; // 85% of actual collateral factor of protocol
        $._slippage = 300; // 3%

        (uint256 _LTV_PRECISION, , , , uint256 _EXCHANGE_PRECISION, , , ) = IFraxlendPair(fraxlendPair_).getConstants();
        $._ltvPrecision = _LTV_PRECISION;
        $._exchangePrecision = _EXCHANGE_PRECISION;
        $._maxLtv = fraxlendPair().maxLTV();
    }

    function borrowToken() public view returns (address) {
        return _getFraxlendV1BorrowStorage()._borrowToken;
    }

    function fraxlendPair() public view returns (IFraxlendPair) {
        return IFraxlendPair(receiptToken());
    }

    function isReservedToken(address token_) public view virtual override returns (bool) {
        return super.isReservedToken(token_) || token_ == borrowToken();
    }

    function maxBorrowLimit() public view returns (uint256) {
        return _getFraxlendV1BorrowStorage()._maxBorrowLimit;
    }

    function minBorrowLimit() public view returns (uint256) {
        return _getFraxlendV1BorrowStorage()._minBorrowLimit;
    }

    function slippage() public view returns (uint256) {
        return _getFraxlendV1BorrowStorage()._slippage;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view override returns (uint256) {
        return fraxlendPair().userCollateralBalance(address(this)) + collateralToken().balanceOf(address(this));
    }

    /// @dev It will make adjustment to maintain safe borrow position.
    /// 1. Check if position needs any adjustment.
    /// 2. Repay borrow tokens if needed.
    /// 3. Borrow more tokens if needed.
    function _adjustBorrowPosition() private {
        //
        // 1. Check if position needs to repay or borrow more
        //
        (uint256 _borrowAmount, uint256 _repayAmount) = _calculateBorrowPosition(0, 0);

        //
        // 2. Repay borrow token to maintain safe position
        //
        if (_repayAmount > 0) {
            _repay(_repayAmount);
        } else if (_borrowAmount > 0) {
            //
            // 3. Borrow tokens from protocol
            //
            _borrow(_borrowAmount);
        }
    }

    /// @dev Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);

        address _swapper = address(swapper());
        IERC20 _collateralToken = collateralToken();
        IERC20 _borrowToken = IERC20(borrowToken());
        address _fraxlendPair = address(fraxlendPair());

        _collateralToken.forceApprove(_fraxlendPair, amount_);
        _collateralToken.forceApprove(_swapper, amount_);
        _borrowToken.forceApprove(_fraxlendPair, amount_);
        _borrowToken.forceApprove(_swapper, amount_);
    }

    /// @dev Borrow tokens from Fraxlend. Deposit borrowed tokens into end protocol, if any.
    function _borrow(uint256 borrowAmount_) private {
        address _borrowToken = borrowToken();
        //
        // 1 Borrow tokens from Fraxlend
        //
        fraxlendPair().borrowAsset(borrowAmount_, 0, address(this));

        //
        // 2 Deposit borrowed tokens into end protocol.
        //
        uint256 _borrowBalance = IERC20(_borrowToken).balanceOf(address(this));
        if (_borrowBalance > 0) {
            _depositBorrowToken(_borrowBalance);
        }
    }

    function _borrowedFromFraxlend() private view returns (uint256) {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        return _fraxlendPair.toBorrowAmount(_fraxlendPair.userBorrowShares(address(this)), true);
    }

    function _calculateBorrow(uint256 collateralAmount_, uint256 exchangeRate_) private view returns (uint256) {
        FraxlendV1BorrowStorage storage $ = _getFraxlendV1BorrowStorage();
        return (collateralAmount_ * $._maxLtv * $._exchangePrecision) / ($._ltvPrecision * exchangeRate_);
    }

    /**
     * @dev Calculate borrow and repay amount based on current collateral and new deposit/withdraw amount.
     * @param depositAmount_ deposit amount
     * @param withdrawAmount_ withdraw amount
     * @return _borrowAmount borrow more amount
     * @return _repayAmount repay amount to keep ltv within limits
     */
    function _calculateBorrowPosition(
        uint256 depositAmount_,
        uint256 withdrawAmount_
    ) private view returns (uint256 _borrowAmount, uint256 _repayAmount) {
        require(depositAmount_ == 0 || withdrawAmount_ == 0, "all-input-gt-zero");
        uint256 _borrowed = _borrowedFromFraxlend();
        // If maximum borrow limit set to 0 then repay borrow
        if (maxBorrowLimit() == 0) {
            return (0, _borrowed);
        }

        IFraxlendPair _fraxlendPair = fraxlendPair();
        uint256 _collateralSupplied = _fraxlendPair.userCollateralBalance(address(this));

        // In case of withdraw, withdrawAmount_ may be greater than _collateralSupplied
        uint256 _hypotheticalCollateral;
        if (depositAmount_ > 0) {
            _hypotheticalCollateral = _collateralSupplied + depositAmount_;
        } else if (_collateralSupplied > withdrawAmount_) {
            _hypotheticalCollateral = _collateralSupplied - withdrawAmount_;
        }
        // It is collateral:asset ratio. i.e. how much collateral to buy 1e18 asset
        uint224 _exchangeRate = _fraxlendPair.exchangeRateInfo().exchangeRate;

        // Max borrow limit in borrow token i.e. FRAX.
        uint256 _maxBorrowPossible = _calculateBorrow(_hypotheticalCollateral, _exchangeRate);

        // If maxBorrow is zero, we should repay total amount of borrow
        if (_maxBorrowPossible == 0) {
            return (0, _borrowed);
        }

        // Safe buffer to avoid liquidation due to price variations.
        uint256 _borrowUpperBound = (_maxBorrowPossible * maxBorrowLimit()) / MAX_BPS;

        // Borrow up to _borrowLowerBound and keep buffer of _borrowUpperBound - _borrowLowerBound for price variation
        uint256 _borrowLowerBound = (_maxBorrowPossible * minBorrowLimit()) / MAX_BPS;

        // If current borrow is greater than max borrow, then repay to achieve safe position else borrow more.
        if (_borrowed > _borrowUpperBound) {
            // If borrow > upperBound then it is greater than lowerBound too.
            _repayAmount = _borrowed - _borrowLowerBound;
        } else if (_borrowed < _borrowLowerBound) {
            _borrowAmount = _borrowLowerBound - _borrowed;
            uint256 _availableLiquidity = _getAvailableLiquidity();
            if (_borrowAmount > _availableLiquidity) {
                _borrowAmount = _availableLiquidity;
            }
        }
    }

    /// @dev Deposit borrowed token.
    /// It is usually called after borrowing tokens from Fraxlend.
    function _depositBorrowToken(uint256 amount_) internal virtual;

    /// @dev Deposit collateral tokens in Fraxlend.
    function _depositCollateral(uint256 amount_) private {
        if (amount_ > 0) {
            fraxlendPair().addCollateral(amount_, address(this));
        }
    }

    function _getAvailableLiquidity() private view returns (uint256) {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        uint256 _totalAsset = _fraxlendPair.totalAsset().amount;
        uint256 _totalBorrow = _fraxlendPair.totalBorrow().amount;
        return _totalAsset > _totalBorrow ? _totalAsset - _totalBorrow : 0;
    }

    /// @dev Get chainlink oracle from fraxlendPair contract
    function _getOracle(address token_) private view returns (address _oracle) {
        if (token_ == borrowToken()) {
            // Oracle multiply is configured for borrowToken aka asset.
            // For FRAX it is set to null as price of FRAX is expected to be $1.
            _oracle = fraxlendPair().oracleMultiply();
        } else {
            // Oracle divide is configured for collateral
            _oracle = fraxlendPair().oracleDivide();
        }
    }

    /// @dev Get Price from oracle. Price has 8 decimals.
    function _getPrice(address token_) private view returns (uint256 _price) {
        address _oracle = _getOracle(token_);
        if (_oracle == address(0)) {
            _price = 1e8;
        } else {
            (, int256 _answer, , , ) = AggregatorV3Interface(_oracle).latestRoundData();
            _price = uint256(_answer);
            if (_price == 0) revert PriceError();
        }
    }

    /// @dev Returns borrowed balance here and deposited into end protocol if any.
    function _getTotalBorrowBalance() internal view virtual returns (uint256) {
        return IERC20(borrowToken()).balanceOf(address(this));
    }

    /**
     * @dev Get quote for token price in terms of other token.
     * @param tokenIn_ tokenIn
     * @param tokenOut_ tokenOut
     * @param amountIn_ amount of tokenIn_
     * @return amountOut of tokenOut_ for amountIn_ of tokenIn_
     */
    function _quote(address tokenIn_, address tokenOut_, uint256 amountIn_) private view returns (uint256) {
        uint256 _tokenInPrice = _getPrice(tokenIn_);
        uint256 _tokenOutPrice = _getPrice(tokenOut_);
        return ((_tokenInPrice * amountIn_ * (10 ** IERC20Metadata(tokenOut_).decimals())) /
            (10 ** IERC20Metadata(tokenIn_).decimals() * _tokenOutPrice));
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        // Accrue and update interest
        _fraxlendPair.addInterest();

        uint256 _borrowed = _borrowedFromFraxlend();
        uint256 _totalBorrowBalance = _getTotalBorrowBalance();
        // _borrow increases every block.
        if (_borrowed > _totalBorrowBalance) {
            // Loss making scenario. Convert collateral to borrowToken to repay loss
            _swapCollateralForBorrow(_borrowed - _totalBorrowBalance);
        } else {
            // excess borrow is profit
            _swapBorrowForCollateral(_totalBorrowBalance - _borrowed);
        }

        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _collateralInFraxlend = _fraxlendPair.userCollateralBalance(address(this));
        uint256 _totalCollateral = _collateralInFraxlend + _collateralHere;

        if (_totalCollateral > _totalDebt) {
            _profit = _totalCollateral - _totalDebt;
        } else {
            _loss = _totalDebt - _totalCollateral;
        }
        uint256 _profitAndExcessDebt = _profit + _excessDebt;
        if (_collateralHere < _profitAndExcessDebt) {
            _withdrawHere(_profitAndExcessDebt - _collateralHere);
            _collateralHere = _collateralToken.balanceOf(address(this));
        }

        // Set actual payback first and then profit. Make sure _collateralHere >= _payback + profit.
        _payback = Math.min(_collateralHere, _excessDebt);
        _profit = _collateralHere > _payback ? Math.min((_collateralHere - _payback), _profit) : 0;

        _pool.reportEarning(_profit, _loss, _payback);

        // Deposit collateral tokens sent by the Vesper pool.
        _depositCollateral(_collateralToken.balanceOf(address(this)));

        _adjustBorrowPosition();
    }

    /// @dev Repay borrow tokens to Fraxlend. Before repay, withdraw borrow tokens from end protocol if any.
    function _repay(uint256 repayAmount_) private {
        //
        // 1. Withdraw borrow tokens from end protocol
        //
        _withdrawBorrowToken(repayAmount_);
        //
        // 2. Repay borrow tokens to Fraxlend
        //
        // Note: _withdrawBorrowToken may withdraw less than repayAmount_ and
        // that will cause repayAsset() to fail. This is desired outcome.
        IFraxlendPair _fraxlendPair = fraxlendPair();
        uint256 _fraxShare = _fraxlendPair.toBorrowShares(
            Math.min(repayAmount_, IERC20(borrowToken()).balanceOf(address(this))),
            false
        );
        _fraxlendPair.repayAsset(_fraxShare, address(this));
    }

    /// @dev Swap excess borrow token for collateral token.
    function _swapBorrowForCollateral(uint256 excessBorrow_) private {
        address _borrowToken = borrowToken();
        address _collateralToken = address(collateralToken());

        if (excessBorrow_ > 0) {
            uint256 _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
            if (excessBorrow_ > _borrowBalanceHere) {
                _withdrawBorrowToken(excessBorrow_ - _borrowBalanceHere);
                _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
            }
            if (_borrowBalanceHere > 0) {
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

    /**
     * @dev Swap collateral to borrowToken
     * @param amountOut_ Expected output of this swap
     */
    function _swapCollateralForBorrow(uint256 amountOut_) private {
        IERC20 _collateralToken = collateralToken();
        address _borrowToken = borrowToken();
        // Looking for _amountIn using fixed output amount
        uint256 _expectedAmountIn = _quote(_borrowToken, address(_collateralToken), amountOut_);
        if (_expectedAmountIn > 0) {
            uint256 _maxAmountIn = (_expectedAmountIn * (MAX_BPS + slippage())) / MAX_BPS;
            uint256 _collateralHere = _collateralToken.balanceOf(address(this));
            // If we do not have enough _from token to get expected output, either get
            // some _from token or adjust expected output.
            if (_maxAmountIn > _collateralHere) {
                // Redeem some collateral, so that we have enough collateral to get expected output
                fraxlendPair().removeCollateral(_maxAmountIn - _collateralHere, address(this));
            }
            swapper().swapExactOutput(address(_collateralToken), _borrowToken, amountOut_, _maxAmountIn, address(this));
        }
    }

    function _withdrawHere(uint256 amount_) internal override {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        // Accrue and update interest
        _fraxlendPair.addInterest();
        (, uint256 _repayAmount) = _calculateBorrowPosition(0, amount_);
        _repay(_repayAmount);

        // Get minimum of amount_ and collateral supplied and _available collateral in Fraxlend
        uint256 _withdrawAmount = Math.min(
            amount_,
            Math.min(_fraxlendPair.userCollateralBalance(address(this)), _fraxlendPair.totalCollateral())
        );
        _fraxlendPair.removeCollateral(_withdrawAmount, address(this));
    }

    function _withdrawBorrowToken(uint256 amount_) internal virtual;

    /************************************************************************************************
     *                          Governor/admin/keeper function                                      *
     ***********************************************************************************************/
    /**
     * @notice Update upper and lower borrow limit. Usually maxBorrowLimit < 100% of actual collateral factor of protocol.
     * @dev It is possible to set 0 as _minBorrowLimit to not borrow anything
     * @param minBorrowLimit_ It is % of actual collateral factor of protocol
     * @param maxBorrowLimit_ It is % of actual collateral factor of protocol
     */
    function updateBorrowLimit(uint256 minBorrowLimit_, uint256 maxBorrowLimit_) external onlyGovernor {
        if (maxBorrowLimit_ >= MAX_BPS) revert InvalidMaxBorrowLimit();

        // set _maxBorrowLimit and _minBorrowLimit to zero to disable borrow;
        if ((maxBorrowLimit_ != 0 || minBorrowLimit_ != 0) && maxBorrowLimit_ <= minBorrowLimit_)
            revert MaxShouldBeHigherThanMin();

        FraxlendV1BorrowStorage storage $ = _getFraxlendV1BorrowStorage();
        emit UpdatedBorrowLimit($._minBorrowLimit, minBorrowLimit_, $._maxBorrowLimit, maxBorrowLimit_);
        // To avoid liquidation due to price variations maxBorrowLimit is a collateral factor that is less than actual collateral factor of protocol
        $._minBorrowLimit = minBorrowLimit_;
        $._maxBorrowLimit = maxBorrowLimit_;
    }

    function updateSlippage(uint256 newSlippage_) external onlyGovernor {
        if (newSlippage_ > MAX_BPS) revert InvalidSlippage();
        FraxlendV1BorrowStorage storage $ = _getFraxlendV1BorrowStorage();
        emit UpdatedSlippage($._slippage, newSlippage_);
        $._slippage = newSlippage_;
    }
}
