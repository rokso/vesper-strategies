// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAToken} from "../../../interfaces/aave/IAToken.sol";
import {IIncentivesController} from "../../../interfaces/aave/IIncentivesController.sol";
import {ILendingPool} from "../../../interfaces/aave/ILendingPool.sol";
import {IAaveOracle} from "../../../interfaces/aave/IAaveOracle.sol";
import {IPoolAddressesProvider} from "../../../interfaces/aave/IPoolAddressesProvider.sol";
import {IProtocolDataProvider} from "../../../interfaces/aave/IProtocolDataProvider.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {Strategy} from "../../Strategy.sol";
import {AaveV3Incentive} from "./AaveV3Incentive.sol";

/// @title Deposit Collateral in Aave and earn interest by depositing borrowed token in a Vesper Pool.
abstract contract AaveV3Borrow is Strategy {
    using SafeERC20 for IERC20;

    error DepositFailed(string reason);
    error IncorrectWithdrawAmount();
    error InvalidInput();
    error InvalidMaxBorrowLimit();
    error InvalidReceiptToken();
    error InvalidSlippage();
    error MaxShouldBeHigherThanMin();
    error PriceError();

    uint256 internal constant MAX_BPS = 10_000; //100%

    event UpdatedBorrowLimit(
        uint256 previousMinBorrowLimit,
        uint256 newMinBorrowLimit,
        uint256 previousMaxBorrowLimit,
        uint256 newMaxBorrowLimit
    );

    event UpdatedSlippage(uint256 previousSlippage, uint256 newSlippage);

    /// @custom:storage-location erc7201:vesper.storage.Strategy.AaveV3Borrow
    struct AaveV3BorrowStorage {
        IPoolAddressesProvider _poolAddressesProvider;
        address _borrowToken;
        IAToken _vdToken; // variable debt token
        address _aBorrowToken;
        IERC20 _wrappedCollateral;
        uint256 _minBorrowLimit;
        uint256 _maxBorrowLimit;
        uint256 _slippage;
    }

    bytes32 private constant AaveV3BorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.AaveV3Borrow")) - 1)) & ~bytes32(uint256(0xff));

    function _getAaveV3BorrowStorage() internal pure returns (AaveV3BorrowStorage storage $) {
        bytes32 _location = AaveV3BorrowStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function __AaveV3Borrow_init(
        address pool_,
        address swapper_,
        address receiptToken_,
        address borrowToken_,
        address poolAddressesProvider_,
        string memory name_
    ) internal initializer {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);

        if (borrowToken_ == address(0) || poolAddressesProvider_ == address(0)) revert AddressIsNull();

        IERC20 _wrappedCollateral = _getWrappedToken(collateralToken());
        if (IAToken(receiptToken_).UNDERLYING_ASSET_ADDRESS() != address(_wrappedCollateral))
            revert InvalidReceiptToken();

        (address _aBorrowToken, , address _vdToken) = IPoolAddressesProvider(poolAddressesProvider_)
            .getPoolDataProvider()
            .getReserveTokensAddresses(borrowToken_);

        AaveV3BorrowStorage storage $ = _getAaveV3BorrowStorage();
        $._poolAddressesProvider = IPoolAddressesProvider(poolAddressesProvider_);
        $._borrowToken = borrowToken_;
        $._vdToken = IAToken(_vdToken);
        $._aBorrowToken = _aBorrowToken;
        $._wrappedCollateral = _wrappedCollateral;

        $._minBorrowLimit = 7_000; // 70% of actual collateral factor of protocol
        $._maxBorrowLimit = 8_500; // 85% of actual collateral factor of protocol
        $._slippage = 300; // 3%
    }

    function aavePoolAddressesProvider() public view returns (IPoolAddressesProvider) {
        return _getAaveV3BorrowStorage()._poolAddressesProvider;
    }

    function aBorrowToken() public view returns (address) {
        return _getAaveV3BorrowStorage()._aBorrowToken;
    }

    function borrowToken() public view returns (address) {
        return _getAaveV3BorrowStorage()._borrowToken;
    }

    function isReservedToken(address token_) public view virtual override returns (bool) {
        return
            token_ == address(collateralToken()) ||
            token_ == receiptToken() ||
            address(vdToken()) == token_ ||
            borrowToken() == token_;
    }

    function maxBorrowLimit() public view returns (uint256) {
        return _getAaveV3BorrowStorage()._maxBorrowLimit;
    }

    function minBorrowLimit() public view returns (uint256) {
        return _getAaveV3BorrowStorage()._minBorrowLimit;
    }

    function slippage() public view returns (uint256) {
        return _getAaveV3BorrowStorage()._slippage;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view virtual override returns (uint256) {
        // receiptToken is aToken. aToken is 1:1 of collateral token
        return IERC20(receiptToken()).balanceOf(address(this)) + collateralToken().balanceOf(address(this));
    }

    function vdToken() public view returns (IAToken) {
        return _getAaveV3BorrowStorage()._vdToken;
    }

    function wrappedCollateral() public view returns (IERC20) {
        return _getAaveV3BorrowStorage()._wrappedCollateral;
    }

    /// @notice After borrowing Y Hook
    function _afterBorrowY(uint256 amount_) internal virtual;

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        address _swapper = address(swapper());
        IERC20 _wrappedCollateral = wrappedCollateral();
        IERC20 _borrowToken = IERC20(borrowToken());
        address _lendingPool = address(aavePoolAddressesProvider().getPool());
        _wrappedCollateral.forceApprove(_lendingPool, amount_);
        _wrappedCollateral.forceApprove(_swapper, amount_);
        _borrowToken.forceApprove(_lendingPool, amount_);
        _borrowToken.forceApprove(_swapper, amount_);
    }

    /// @notice Before repaying Y Hook
    function _beforeRepayY(uint256 amount_) internal virtual;

    /**
     * @notice Calculate borrow and repay amount based on current collateral and new deposit/withdraw amount.
     * @param depositAmount_ wrapped collateral amount to deposit
     * @param withdrawAmount_ wrapped collateral amount to withdraw
     * @param borrowed_ borrowed from protocol
     * @param supplied_ wrapped collateral supplied to protocol
     * @return _borrowAmount borrow more amount
     * @return _repayAmount repay amount to keep ltv within limit
     */
    function _calculateBorrowPosition(
        uint256 depositAmount_,
        uint256 withdrawAmount_,
        uint256 borrowed_,
        uint256 supplied_
    ) internal view returns (uint256 _borrowAmount, uint256 _repayAmount) {
        if (depositAmount_ != 0 && withdrawAmount_ != 0) revert InvalidInput();
        // If maximum borrow limit set to 0 then repay borrow
        if (maxBorrowLimit() == 0) {
            return (0, borrowed_);
        }
        // In case of withdraw, _amount can be greater than _supply
        uint256 _hypotheticalCollateral = depositAmount_ > 0 ? supplied_ + depositAmount_ : supplied_ > withdrawAmount_
            ? supplied_ - withdrawAmount_
            : 0;
        if (_hypotheticalCollateral == 0) {
            return (0, borrowed_);
        }
        IAaveOracle _aaveOracle = aavePoolAddressesProvider().getPriceOracle();
        address _borrowToken = borrowToken();
        address _wrappedCollateral = address(wrappedCollateral());
        uint256 _borrowTokenPrice = _aaveOracle.getAssetPrice(_borrowToken);
        uint256 _collateralTokenPrice = _aaveOracle.getAssetPrice(_wrappedCollateral);
        if (_borrowTokenPrice == 0 || _collateralTokenPrice == 0) {
            // Oracle problem. Lets payback all
            return (0, borrowed_);
        }
        // _collateralFactor in 4 decimal. 10_000 = 100%
        (, uint256 _collateralFactor, , , , , , , , ) = aavePoolAddressesProvider()
            .getPoolDataProvider()
            .getReserveConfigurationData(_wrappedCollateral);

        // Collateral in base currency based on oracle price and cf;
        uint256 _actualCollateralForBorrow = (_hypotheticalCollateral * _collateralFactor * _collateralTokenPrice) /
            (MAX_BPS * (10 ** IERC20Metadata(_wrappedCollateral).decimals()));
        // Calculate max borrow possible in borrow token number
        uint256 _maxBorrowPossible = (_actualCollateralForBorrow * (10 ** IERC20Metadata(_borrowToken).decimals())) /
            _borrowTokenPrice;
        if (_maxBorrowPossible == 0) {
            return (0, borrowed_);
        }
        // Safe buffer to avoid liquidation due to price variations.
        uint256 _borrowUpperBound = (_maxBorrowPossible * maxBorrowLimit()) / MAX_BPS;

        // Borrow up to _borrowLowerBound and keep buffer of _borrowUpperBound - _borrowLowerBound for price variation
        uint256 _borrowLowerBound = (_maxBorrowPossible * minBorrowLimit()) / MAX_BPS;

        // If current borrow is greater than max borrow, then repay to achieve safe position.
        if (borrowed_ > _borrowUpperBound) {
            // If borrow > upperBound then it is greater than lowerBound too.
            _repayAmount = borrowed_ - _borrowLowerBound;
        } else if (_borrowLowerBound > borrowed_) {
            _borrowAmount = _borrowLowerBound - borrowed_;
            uint256 _availableLiquidity = IERC20(_borrowToken).balanceOf(aBorrowToken());
            if (_borrowAmount > _availableLiquidity) {
                _borrowAmount = _availableLiquidity;
            }
        }
    }

    function _calculateUnwrapped(uint256 wrappedAmount_) internal view virtual returns (uint256) {
        return wrappedAmount_;
    }

    function _calculateWrapped(uint256 unwrappedAmount_) internal view virtual returns (uint256) {
        return unwrappedAmount_;
    }

    /// @dev Override function defined in Strategy.sol to claim all rewards from protocol.
    function _claimRewards() internal override {
        AaveV3Incentive._claimRewards(receiptToken());
    }

    function _depositToAave(uint256 amount_, ILendingPool aaveLendingPool_) internal virtual {
        uint256 _wrappedAmount = _wrap(amount_);
        if (_wrappedAmount > 0) {
            // solhint-disable-next-line no-empty-blocks
            try aaveLendingPool_.supply(address(wrappedCollateral()), _wrappedAmount, address(this), 0) {} catch Error(
                string memory _reason
            ) {
                // Aave uses liquidityIndex and some other indexes as needed to normalize input.
                // If normalized input equals to 0 then error will be thrown with '56' error code.
                // CT_INVALID_MINT_AMOUNT = '56'; //invalid amount to mint
                // Hence discard error where error code is '56'
                if (bytes32(bytes(_reason)) != "56") revert DepositFailed(_reason);
            }
        }
    }

    function _getCollateralHere() internal virtual returns (uint256) {
        return collateralToken().balanceOf(address(this));
    }

    /// @notice Borrowed Y balance deposited here or elsewhere hook
    function _getInvestedBorrowBalance() internal view virtual returns (uint256) {
        return IERC20(borrowToken()).balanceOf(address(this));
    }

    function _getWrappedToken(IERC20 unwrappedToken_) internal view virtual returns (IERC20) {
        return unwrappedToken_;
    }

    /**
     * @dev get quote for token price in terms of other token.
     * @param tokenIn_ tokenIn
     * @param tokenOut_ tokenOut
     * @param amountIn_ amount of tokenIn_
     * @return _amountOut amount of tokenOut_ for amountIn_ of tokenIn_
     */
    function _quote(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_
    ) internal view virtual returns (uint256 _amountOut) {
        IAaveOracle _aaveOracle = aavePoolAddressesProvider().getPriceOracle();
        // Aave oracle prices are in WETH. Price is in 18 decimal.
        uint256 _tokenInPrice = _aaveOracle.getAssetPrice(tokenIn_);
        uint256 _tokenOutPrice = _aaveOracle.getAssetPrice(tokenOut_);
        if (_tokenInPrice == 0 || _tokenOutPrice == 0) revert PriceError();
        _amountOut =
            (((_tokenInPrice * amountIn_) / 10 ** IERC20Metadata(tokenIn_).decimals()) *
                (10 ** IERC20Metadata(tokenOut_).decimals())) /
            _tokenOutPrice;
    }

    /**
     * @dev Generate report for pools accounting and also send profit and any payback to pool.
     */
    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        // NOTE:: Pool has unwrapped as collateral and any state is also unwrapped amount
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _borrowed = vdToken().balanceOf(address(this));
        uint256 _investedBorrowBalance = _getInvestedBorrowBalance();
        ILendingPool _lendingPool = aavePoolAddressesProvider().getPool();

        // _borrow increases every block. Convert collateral to borrowToken.
        if (_borrowed > _investedBorrowBalance) {
            // Loss making scenario. Convert collateral to borrowToken to repay loss
            _swapToBorrowToken(_borrowed - _investedBorrowBalance, _lendingPool);
        } else {
            // Swap extra borrow token to collateral token and report profit
            _rebalanceBorrow(_investedBorrowBalance - _borrowed);
        }
        uint256 _collateralHere = _getCollateralHere();
        uint256 _supplied = IERC20(receiptToken()).balanceOf(address(this));
        uint256 _unwrappedSupplied = _calculateUnwrapped(_supplied);
        uint256 _totalCollateral = _unwrappedSupplied + _collateralHere;
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        if (_totalCollateral > _totalDebt) {
            _profit = _totalCollateral - _totalDebt;
        } else {
            _loss = _totalDebt - _totalCollateral;
        }
        uint256 _profitAndExcessDebt = _profit + _excessDebt;
        if (_collateralHere < _profitAndExcessDebt) {
            uint256 _totalAmountToWithdraw = Math.min((_profitAndExcessDebt - _collateralHere), _unwrappedSupplied);
            if (_totalAmountToWithdraw > 0) {
                _withdrawHere(_totalAmountToWithdraw, _lendingPool, _borrowed, _supplied);
                _collateralHere = collateralToken().balanceOf(address(this));
            }
        }

        // Make sure _collateralHere >= _payback + profit. set actual payback first and then profit
        _payback = Math.min(_collateralHere, _excessDebt);
        _profit = _collateralHere > _payback ? Math.min((_collateralHere - _payback), _profit) : 0;

        _pool.reportEarning(_profit, _loss, _payback);
        // This is unwrapped balance if pool supports unwrap token eg stETH
        uint256 _newSupply = collateralToken().balanceOf(address(this));
        if (_newSupply > 0) {
            _depositToAave(_newSupply, _lendingPool);
        }

        // There are scenarios when we want to call _calculateBorrowPosition and act on it.
        // 1. Strategy got some collateral from pool which will allow strategy to borrow more.
        // 2. Collateral and/or borrow token price is changed which leads to repay or borrow.
        // 3. BorrowLimits are updated.
        // In some edge scenarios, below call is redundant but keeping it as is for simplicity.
        (uint256 _borrowAmount, uint256 _repayAmount) = _calculateBorrowPosition(
            0,
            0,
            vdToken().balanceOf(address(this)),
            IERC20(receiptToken()).balanceOf(address(this))
        );
        address _borrowToken = borrowToken();
        if (_repayAmount > 0) {
            // Repay _borrowAmount to maintain safe position
            _repayY(_repayAmount, _lendingPool);
        } else if (_borrowAmount > 0) {
            // 2 for variable rate borrow, 0 for referralCode
            _lendingPool.borrow(_borrowToken, _borrowAmount, 2, 0, address(this));
        }
        uint256 _borrowTokenBalance = IERC20(_borrowToken).balanceOf(address(this));
        if (_borrowTokenBalance > 0) {
            _afterBorrowY(_borrowTokenBalance);
        }
    }

    /// @notice Swap earned borrow token for collateral and report it as profits
    function _rebalanceBorrow(uint256 excessBorrow_) internal {
        address _borrowToken = borrowToken();
        address _wrappedCollateral = address(wrappedCollateral());
        if (excessBorrow_ > 0) {
            uint256 _borrowedHere = IERC20(_borrowToken).balanceOf(address(this));
            if (excessBorrow_ > _borrowedHere) {
                _withdrawY(excessBorrow_ - _borrowedHere);
                _borrowedHere = IERC20(_borrowToken).balanceOf(address(this));
            }
            if (_borrowedHere > 0) {
                // Swap minimum of _excessBorrow and _borrowedHere for collateral
                uint256 _amountIn = Math.min(excessBorrow_, _borrowedHere);
                uint256 _expectedAmountOut = _quote(_borrowToken, _wrappedCollateral, _amountIn);
                uint256 _minAmountOut = (_expectedAmountOut * (MAX_BPS - slippage())) / MAX_BPS;
                swapper().swapExactInput(_borrowToken, _wrappedCollateral, _amountIn, _minAmountOut, address(this));
            }
        }
    }

    function _repayY(uint256 amount_, ILendingPool aaveLendingPool_) internal virtual {
        _beforeRepayY(amount_);
        aaveLendingPool_.repay(borrowToken(), amount_, 2, address(this));
    }

    /**
     * @dev Swap collateral to borrow token.
     * @param amountOut_ Expected output of this swap
     * @param aaveLendingPool_ Aave lending pool instance
     */
    function _swapToBorrowToken(uint256 amountOut_, ILendingPool aaveLendingPool_) internal {
        address _borrowToken = borrowToken();
        address _wrappedCollateral = address(wrappedCollateral());
        // Looking for _amountIn using fixed output amount
        uint256 _expectedAmountIn = _quote(_borrowToken, _wrappedCollateral, amountOut_);

        if (_expectedAmountIn > 0) {
            uint256 _maxAmountIn = (_expectedAmountIn * (MAX_BPS + slippage())) / MAX_BPS;
            // Not using unwrapped balance here as those can be used in rebalance reporting via getCollateralHere
            uint256 _collateralHere = IERC20(_wrappedCollateral).balanceOf(address(this));
            if (_maxAmountIn > _collateralHere) {
                // Withdraw some collateral from Aave so that we have enough collateral to get expected output
                uint256 _amount = _maxAmountIn - _collateralHere;
                if (aaveLendingPool_.withdraw(_wrappedCollateral, _amount, address(this)) != _amount)
                    revert IncorrectWithdrawAmount();
            }
            swapper().swapExactOutput(_wrappedCollateral, _borrowToken, amountOut_, _maxAmountIn, address(this));
        }
    }

    function _unwrap(uint256 wrappedAmount_) internal virtual returns (uint256) {
        return wrappedAmount_;
    }

    function _wrap(uint256 unwrappedAmount_) internal virtual returns (uint256) {
        return unwrappedAmount_;
    }

    function _withdrawY(uint256 amount_) internal virtual;

    /// @dev If pool supports unwrapped token(stETH) then input and output both are unwrapped token amount.
    function _withdrawHere(uint256 requireAmount_) internal override {
        _withdrawHere(
            requireAmount_,
            aavePoolAddressesProvider().getPool(),
            vdToken().balanceOf(address(this)),
            IERC20(receiptToken()).balanceOf(address(this))
        );
    }

    /**
     * @dev If pool supports unwrapped token(stETH) then _requireAmount and output both are unwrapped token amount.
     * @param requireAmount_ unwrapped collateral amount
     * @param supplied_ wrapped collateral amount
     */
    function _withdrawHere(
        uint256 requireAmount_,
        ILendingPool aaveLendingPool_,
        uint256 borrowed_,
        uint256 supplied_
    ) internal {
        IERC20 _wrappedCollateral = wrappedCollateral();
        uint256 _wrappedRequireAmount = _calculateWrapped(requireAmount_);
        (, uint256 _repayAmount) = _calculateBorrowPosition(0, _wrappedRequireAmount, borrowed_, supplied_);
        if (_repayAmount > 0) {
            _repayY(_repayAmount, aaveLendingPool_);
        }
        // withdraw asking more than available liquidity will fail. To do safe withdraw, check
        // _wrappedRequireAmount against available liquidity.
        uint256 _possibleWithdraw = Math.min(
            _wrappedRequireAmount,
            Math.min(supplied_, _wrappedCollateral.balanceOf(receiptToken()))
        );
        if (
            aaveLendingPool_.withdraw(address(_wrappedCollateral), _possibleWithdraw, address(this)) !=
            _possibleWithdraw
        ) revert IncorrectWithdrawAmount();
        // Unwrap wrapped tokens
        _unwrap(_wrappedCollateral.balanceOf(address(this)));
    }

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

        AaveV3BorrowStorage storage $ = _getAaveV3BorrowStorage();
        emit UpdatedBorrowLimit($._minBorrowLimit, minBorrowLimit_, $._maxBorrowLimit, maxBorrowLimit_);
        // To avoid liquidation due to price variations maxBorrowLimit is a collateral factor that is less than actual collateral factor of protocol
        $._minBorrowLimit = minBorrowLimit_;
        $._maxBorrowLimit = maxBorrowLimit_;
    }

    function updateSlippage(uint256 newSlippage_) external onlyGovernor {
        if (newSlippage_ > MAX_BPS) revert InvalidSlippage();
        AaveV3BorrowStorage storage $ = _getAaveV3BorrowStorage();
        emit UpdatedSlippage($._slippage, newSlippage_);
        $._slippage = newSlippage_;
    }
}
