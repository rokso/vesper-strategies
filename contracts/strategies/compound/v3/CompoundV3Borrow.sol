// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../../Strategy.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {IComet} from "../../../interfaces/compound/IComet.sol";

// solhint-disable no-empty-blocks

/// @title This is base strategy for CompoundV3 borrow.
/// This strategy will deposit collateral token in Compound V3 and based on position it will
/// borrow based token. Supply X borrow Y and keep borrowed amount here.
abstract contract CompoundV3Borrow is Strategy {
    using SafeERC20 for IERC20;

    error InvalidInput();
    error InvalidMaxBorrowLimit();
    error InvalidSlippage();
    error MaxShouldBeHigherThanMin();
    error PriceError();

    event UpdatedBorrowLimit(
        uint256 previousMinBorrowLimit,
        uint256 newMinBorrowLimit,
        uint256 previousMaxBorrowLimit,
        uint256 newMaxBorrowLimit
    );
    event UpdatedSlippage(uint256 previousSlippage, uint256 newSlippage);

    uint256 private constant MAX_BPS = 10_000; //100%
    /// @custom:storage-location erc7201:vesper.storage.Strategy.CompoundV3Borrow
    struct CompoundV3BorrowStorage {
        IComet _comet;
        address _borrowToken;
        uint256 _minBorrowLimit;
        uint256 _maxBorrowLimit;
        uint256 _slippage;
    }

    bytes32 private constant CompoundV3BorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.CompoundV3Borrow")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getCompoundV3BorrowStorage() private pure returns (CompoundV3BorrowStorage storage $) {
        bytes32 _location = CompoundV3BorrowStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function __CompoundV3Borrow_init(
        address pool_,
        address swapper_,
        address comet_,
        address borrowToken_,
        string memory name_
    ) internal onlyInitializing {
        __Strategy_init(pool_, swapper_, comet_, name_);
        if (borrowToken_ == address(0)) revert AddressIsNull();

        CompoundV3BorrowStorage storage $ = _getCompoundV3BorrowStorage();
        $._comet = IComet(comet_);
        $._borrowToken = borrowToken_;

        $._minBorrowLimit = 7_000; // 70% of actual collateral factor of protocol
        $._maxBorrowLimit = 8_500; // 85% of actual collateral factor of protocol
        $._slippage = 300; // 3%
    }

    function borrowToken() public view returns (address) {
        return _getCompoundV3BorrowStorage()._borrowToken;
    }

    function comet() public view returns (IComet) {
        return _getCompoundV3BorrowStorage()._comet;
    }

    function isReservedToken(address token_) public view virtual override returns (bool) {
        return super.isReservedToken(token_) || token_ == borrowToken();
    }

    function maxBorrowLimit() public view returns (uint256) {
        return _getCompoundV3BorrowStorage()._maxBorrowLimit;
    }

    function minBorrowLimit() public view returns (uint256) {
        return _getCompoundV3BorrowStorage()._minBorrowLimit;
    }

    function slippage() public view returns (uint256) {
        return _getCompoundV3BorrowStorage()._slippage;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view override returns (uint256) {
        IERC20 _collateralToken = collateralToken();
        return
            comet().collateralBalanceOf(address(this), address(_collateralToken)) +
            _collateralToken.balanceOf(address(this));
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
        //
        // 4. Deposit borrow tokens into the end protocol, if any.
        //
        // In ideal scenario we get borrow balance from _borrow() and deposit
        // should be called right after _borrow() inside `else if`.
        // If borrow balance is non zero and `if` conditions doesn't meet then
        // borrow balance will sit idle and not generate yield.
        uint256 _borrowBalanceHere = IERC20(borrowToken()).balanceOf(address(this));
        if (_borrowBalanceHere > 0) {
            _depositBorrowToken(_borrowBalanceHere);
        }
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        address _swapper = address(swapper());
        address _comet = address(comet());
        IERC20 _collateralToken = collateralToken();
        IERC20 _borrowToken = IERC20(borrowToken());
        _collateralToken.forceApprove(_comet, amount_);
        _collateralToken.forceApprove(_swapper, amount_);
        _borrowToken.forceApprove(_comet, amount_);
        _borrowToken.forceApprove(_swapper, amount_);
    }

    /// @dev Borrow tokens from Compound.
    function _borrow(uint256 borrowAmount_) private {
        address _borrowToken = borrowToken();
        //
        // 1 Borrow tokens from Compound
        //
        comet().withdraw(_borrowToken, borrowAmount_);
    }

    /**
     * @notice Calculate borrow and repay amount based on current collateral and new deposit/withdraw amount.
     * @param depositAmount_ deposit amount
     * @param withdrawAmount_ withdraw amount
     * @return _borrowAmount borrow more amount
     * @return _repayAmount repay amount to keep ltv within limits
     */
    function _calculateBorrowPosition(
        uint256 depositAmount_,
        uint256 withdrawAmount_
    ) private view returns (uint256 _borrowAmount, uint256 _repayAmount) {
        if (depositAmount_ != 0 && withdrawAmount_ != 0) revert InvalidInput();
        IComet _comet = comet();
        address _collateralToken = address(collateralToken());
        uint256 _borrowed = _comet.borrowBalanceOf(address(this));
        // If maximum borrow limit set to 0 then repay borrow
        if (maxBorrowLimit() == 0) {
            return (0, _borrowed);
        }

        uint256 _collateralSupplied = _comet.collateralBalanceOf(address(this), _collateralToken);

        // In case of withdraw, withdrawAmount_ may be greater than _collateralSupplied
        uint256 _hypotheticalCollateral;
        if (depositAmount_ > 0) {
            _hypotheticalCollateral = _collateralSupplied + depositAmount_;
        } else if (_collateralSupplied > withdrawAmount_) {
            _hypotheticalCollateral = _collateralSupplied - withdrawAmount_;
        }

        IComet.AssetInfo memory _collateralInfo = _comet.getAssetInfoByAddress(_collateralToken);

        // Compound V3 is using chainlink for price feed. Feed has 8 decimals
        uint256 _collateralTokenPrice = _comet.getPrice(_collateralInfo.priceFeed);
        uint256 _borrowTokenPrice = _comet.getPrice(_comet.baseTokenPriceFeed());

        // Calculate max borrow based on collateral factor. CF is 18 decimal based
        uint256 _collateralForBorrowInUSD = (_hypotheticalCollateral *
            _collateralTokenPrice *
            _collateralInfo.borrowCollateralFactor) / (1e18 * 10 ** IERC20Metadata(_collateralToken).decimals());

        // Max borrow limit in borrow token
        uint256 _maxBorrowPossible = (_collateralForBorrowInUSD * 10 ** IERC20Metadata(borrowToken()).decimals()) /
            _borrowTokenPrice;
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
        } else if (_borrowLowerBound > _borrowed) {
            _borrowAmount = _borrowLowerBound - _borrowed;
            uint256 _availableLiquidity = _getAvailableLiquidity();
            if (_borrowAmount > _availableLiquidity) {
                _borrowAmount = _availableLiquidity;
            }
        }
    }

    /// @dev Deposit borrowed token.
    /// It is usually called after borrowing tokens from Compound.
    function _depositBorrowToken(uint256 amount_) internal virtual;

    /// @dev Deposit collateral in Compound.
    function _depositCollateral(uint256 amount_) private {
        if (amount_ > 0) {
            comet().supply(address(collateralToken()), amount_);
        }
    }

    function _getAvailableLiquidity() private view returns (uint256) {
        IComet _comet = comet();
        uint256 _totalSupply = _comet.totalSupply();
        uint256 _totalBorrow = _comet.totalBorrow();
        return _totalSupply > _totalBorrow ? _totalSupply - _totalBorrow : 0;
    }

    /// @dev Returns borrowed balance here and deposited into end protocol if any.
    function _getTotalBorrowBalance() internal view virtual returns (uint256) {
        return IERC20(borrowToken()).balanceOf(address(this));
    }

    function _getPriceFeed(CompoundV3BorrowStorage memory s, address token_) private view returns (address) {
        return
            token_ == s._borrowToken ? s._comet.baseTokenPriceFeed() : s._comet.getAssetInfoByAddress(token_).priceFeed;
    }

    /**
     * @dev Get quote for token price in terms of other token.
     * @param tokenIn_ tokenIn
     * @param tokenOut_ tokenOut
     * @param amountIn_ amount of tokenIn_
     * @return amountOut of tokenOut_ for amountIn_ of tokenIn_
     */
    function _quote(address tokenIn_, address tokenOut_, uint256 amountIn_) private view returns (uint256) {
        CompoundV3BorrowStorage memory s = _getCompoundV3BorrowStorage();
        uint256 _tokenInPrice = s._comet.getPrice(_getPriceFeed(s, tokenIn_));
        uint256 _tokenOutPrice = s._comet.getPrice(_getPriceFeed(s, tokenOut_));

        if (_tokenInPrice == 0 || _tokenOutPrice == 0) revert PriceError();
        return ((_tokenInPrice * amountIn_ * (10 ** IERC20Metadata(tokenOut_).decimals())) /
            (10 ** IERC20Metadata(tokenIn_).decimals() * _tokenOutPrice));
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IComet _comet = comet();
        uint256 _borrowed = _comet.borrowBalanceOf(address(this));
        uint256 _totalBorrowBalance = _getTotalBorrowBalance();
        // _borrow increases every block.
        if (_borrowed > _totalBorrowBalance) {
            // Loss making scenario. Convert collateral to borrowToken to repay loss
            _swapCollateralForBorrow(_borrowed - _totalBorrowBalance);
        } else {
            // excess borrow is profit
            _swapBorrowForCollateral(_totalBorrowBalance - _borrowed);
        }

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _collateralHere +
            _comet.collateralBalanceOf(address(this), address(_collateralToken));

        if (_totalCollateral > _totalDebt) {
            _profit = _totalCollateral - _totalDebt;
        } else {
            _loss = _totalDebt - _totalCollateral;
        }

        uint256 _profitAndExcessDebt = _profit + _excessDebt;
        if (_collateralHere < _profitAndExcessDebt) {
            uint256 _totalAmountToWithdraw = _profitAndExcessDebt - _collateralHere;
            if (_totalAmountToWithdraw > 0) {
                _withdrawHere(_totalAmountToWithdraw);
                _collateralHere = _collateralToken.balanceOf(address(this));
            }
        }
        // Set actual payback first and then profit. Make sure _collateralHere >= _payback + profit.
        _payback = Math.min(_collateralHere, _excessDebt);
        _profit = _collateralHere > _payback ? Math.min((_collateralHere - _payback), _profit) : 0;
        // Report earning to pool
        _pool.reportEarning(_profit, _loss, _payback);

        // Deposit collateral tokens.
        _depositCollateral(_collateralToken.balanceOf(address(this)));

        _adjustBorrowPosition();
    }

    /// @dev Repay borrow tokens to Compound. Before repay, withdraw borrow tokens from end protocol if any.
    function _repay(uint256 repayAmount_) private {
        address _borrowToken = borrowToken();
        //
        // 1. Withdraw borrow tokens from end protocol
        //
        uint256 _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
        if (repayAmount_ > _borrowBalanceHere) {
            _withdrawBorrowToken(repayAmount_ - _borrowBalanceHere);
        }
        //
        // 2. Repay borrow tokens to Compound
        //
        // Note: _withdrawBorrowToken may withdraw less than repayAmount_ and
        // that will cause supply() to fail. This is desired outcome.
        comet().supply(borrowToken(), repayAmount_);
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
        // Get quote for _amountOut of borrowToken to collateralToken
        uint256 _expectedAmountIn = _quote(_borrowToken, address(_collateralToken), amountOut_);
        if (_expectedAmountIn > 0) {
            uint256 _maxAmountIn = (_expectedAmountIn * (MAX_BPS + slippage())) / MAX_BPS;
            uint256 _collateralHere = _collateralToken.balanceOf(address(this));
            // If we do not have enough collateral, withdraw from Compound.
            if (_maxAmountIn > _collateralHere) {
                // Withdraw some collateral, so that we have enough collateral to get expected output
                comet().withdraw(address(_collateralToken), _maxAmountIn - _collateralHere);
            }
            swapper().swapExactOutput(address(_collateralToken), _borrowToken, amountOut_, _maxAmountIn, address(this));
        }
    }

    /// @dev Withdraw collateral here. Do not transfer to pool
    function _withdrawHere(uint256 amount_) internal override {
        (, uint256 _repayAmount) = _calculateBorrowPosition(0, amount_);
        if (_repayAmount > 0) {
            _repay(_repayAmount);
        }
        IComet _comet = comet();
        address _collateralToken = address(collateralToken());
        // Get minimum of amount_ and collateral supplied and _availableLiquidity of collateral
        uint256 _withdrawAmount = Math.min(
            amount_,
            Math.min(
                _comet.collateralBalanceOf(address(this), _collateralToken),
                _comet.totalsCollateral(_collateralToken).totalSupplyAsset
            )
        );
        _comet.withdraw(_collateralToken, _withdrawAmount);
    }

    function _withdrawBorrowToken(uint256 _amount) internal virtual;

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

        CompoundV3BorrowStorage storage $ = _getCompoundV3BorrowStorage();
        emit UpdatedBorrowLimit($._minBorrowLimit, minBorrowLimit_, $._maxBorrowLimit, maxBorrowLimit_);
        // To avoid liquidation due to price variations maxBorrowLimit is a collateral factor that is less than actual collateral factor of protocol
        $._minBorrowLimit = minBorrowLimit_;
        $._maxBorrowLimit = maxBorrowLimit_;
    }

    function updateSlippage(uint256 newSlippage_) external onlyGovernor {
        if (newSlippage_ > MAX_BPS) revert InvalidSlippage();
        CompoundV3BorrowStorage storage $ = _getCompoundV3BorrowStorage();
        emit UpdatedSlippage($._slippage, newSlippage_);
        $._slippage = newSlippage_;
    }
}
