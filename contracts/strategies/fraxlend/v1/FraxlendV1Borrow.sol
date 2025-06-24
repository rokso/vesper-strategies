// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BorrowStrategy} from "../../BorrowStrategy.sol";
import {AggregatorV3Interface} from "../../../interfaces/chainlink/AggregatorV3Interface.sol";
import {IFraxlendPair} from "../../../interfaces/fraxlend/IFraxlendPair.sol";

// solhint-disable var-name-mixedcase

/// @title This strategy will deposit collateral token in Fraxlend and based on position it will
/// borrow Frax.
abstract contract FraxlendV1Borrow is BorrowStrategy {
    using SafeERC20 for IERC20;

    error BorrowTokenMismatch();
    error CollateralTokenMismatch();
    error PriceError();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.FraxlendV1Borrow
    struct FraxlendV1BorrowStorage {
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
        __Borrow_init(pool_, swapper_, fraxlendPair_, borrowToken_, name_);

        if (IFraxlendPair(fraxlendPair_).asset() != borrowToken_) revert BorrowTokenMismatch();
        if (IFraxlendPair(fraxlendPair_).collateralContract() != address(collateralToken()))
            revert CollateralTokenMismatch();

        FraxlendV1BorrowStorage storage $ = _getFraxlendV1BorrowStorage();

        (uint256 _LTV_PRECISION, , , , uint256 _EXCHANGE_PRECISION, , , ) = IFraxlendPair(fraxlendPair_).getConstants();
        $._ltvPrecision = _LTV_PRECISION;
        $._exchangePrecision = _EXCHANGE_PRECISION;
        $._maxLtv = IFraxlendPair(fraxlendPair_).maxLTV();
    }

    function fraxlendPair() public view returns (IFraxlendPair) {
        return IFraxlendPair(receiptToken());
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view override returns (uint256) {
        return _getSupplied() + collateralToken().balanceOf(address(this));
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

    /// @dev Borrow tokens from Fraxlend.
    function _borrow(uint256 borrowAmount_) internal override {
        fraxlendPair().borrowAsset(borrowAmount_, 0, address(this));
    }

    function _calculateBorrowPosition(
        uint256 amount_,
        bool isDeposit_
    ) internal view override returns (uint256 _borrowAmount, uint256 _repayAmount) {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        uint256 _borrowed = _fraxlendPair.toBorrowAmount(_fraxlendPair.userBorrowShares(address(this)), true);

        // If maximum borrow limit set to 0 then repay borrow
        if (maxBorrowLimit() == 0) {
            return (0, _borrowed);
        }

        uint256 _collateralSupplied = _fraxlendPair.userCollateralBalance(address(this));

        // In case of withdraw, amount_ may be greater than _collateralSupplied
        uint256 _hypotheticalCollateral;
        if (isDeposit_) {
            _hypotheticalCollateral = _collateralSupplied + amount_;
        } else if (!isDeposit_ && _collateralSupplied > amount_) {
            _hypotheticalCollateral = _collateralSupplied - amount_;
        }
        if (_hypotheticalCollateral == 0) {
            return (0, _borrowed);
        }
        // It is collateral:asset ratio. i.e. how much collateral to buy 1e18 asset
        uint224 _exchangeRate = _fraxlendPair.exchangeRateInfo().exchangeRate;

        FraxlendV1BorrowStorage memory s = _getFraxlendV1BorrowStorage();
        // Max borrow limit in borrow token i.e. FRAX.
        uint256 _maxBorrowPossible = (_hypotheticalCollateral * s._maxLtv * s._exchangePrecision) /
            (s._ltvPrecision * _exchangeRate);

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

    /// @dev Deposit collateral tokens in Fraxlend.
    function _depositCollateral(uint256 amount_) internal override {
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

    function _getBorrowed() internal view override returns (uint256) {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        return _fraxlendPair.toBorrowAmount(_fraxlendPair.userBorrowShares(address(this)), true);
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

    function _getSupplied() internal view override returns (uint256) {
        return fraxlendPair().userCollateralBalance(address(this));
    }

    function _quote(address tokenIn_, address tokenOut_, uint256 amountIn_) internal view override returns (uint256) {
        uint256 _tokenInPrice = _getPrice(tokenIn_);
        uint256 _tokenOutPrice = _getPrice(tokenOut_);
        return ((_tokenInPrice * amountIn_ * (10 ** IERC20Metadata(tokenOut_).decimals())) /
            (10 ** IERC20Metadata(tokenIn_).decimals() * _tokenOutPrice));
    }

    function _rebalance() internal override returns (uint256, uint256, uint256) {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        // Accrue and update interest
        _fraxlendPair.addInterest();
        // Update exchange rate
        _fraxlendPair.updateExchangeRate();

        return super._rebalance();
    }

    /// @dev Repay borrow tokens to Fraxlend.
    function _repay(uint256 repayAmount_) internal override {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        uint256 _fraxShare = _fraxlendPair.toBorrowShares(repayAmount_, false);
        _fraxlendPair.repayAsset(_fraxShare, address(this));
    }

    function _withdrawCollateral(uint256 amount_) internal override {
        fraxlendPair().removeCollateral(amount_, address(this));
    }

    function _withdrawHere(uint256 amount_) internal override {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        // Accrue and update interest
        _fraxlendPair.addInterest();
        // Adjust position based on withdrawal of amount_.
        // Setting false for withdraw
        _adjustBorrowPosition(amount_, false);

        // Get minimum of amount_ and collateral supplied and _available collateral in Fraxlend
        uint256 _withdrawAmount = Math.min(
            amount_,
            Math.min(_fraxlendPair.userCollateralBalance(address(this)), _fraxlendPair.totalCollateral())
        );
        _fraxlendPair.removeCollateral(_withdrawAmount, address(this));
    }
}
