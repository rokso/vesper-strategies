// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../../Strategy.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {ISwapper} from "../../../interfaces/swapper/ISwapper.sol";
import {IComet} from "../../../interfaces/compound/IComet.sol";

// solhint-disable no-empty-blocks

/// @title This is base strategy for CompoundV3 borrow.
/// This strategy will deposit collateral token in Compound V3 and based on position it will
/// borrow based token. Supply X borrow Y and keep borrowed amount here.
abstract contract CompoundV3Borrow is Strategy {
    using SafeERC20 for IERC20;

    error InvalidInput();
    error InvalidMaxBorrowLimit();
    error MaxShouldBeHigherThanMin();

    event UpdatedBorrowLimit(
        uint256 previousMinBorrowLimit,
        uint256 newMinBorrowLimit,
        uint256 previousMaxBorrowLimit,
        uint256 newMaxBorrowLimit
    );

    uint256 internal constant MAX_BPS = 10_000; //100%
    /// @custom:storage-location erc7201:vesper.storage.Strategy.CompoundV3Borrow
    struct CompoundV3BorrowStorage {
        IComet _comet;
        address _borrowToken;
        uint256 _minBorrowLimit;
        uint256 _maxBorrowLimit;
    }

    bytes32 private constant CompoundV3BorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.CompoundV3Borrow")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getCompoundV3BorrowStorage() internal pure returns (CompoundV3BorrowStorage storage $) {
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
    ) internal initializer {
        __Strategy_init(pool_, swapper_, comet_, name_);
        if (borrowToken_ == address(0)) revert AddressIsNull();

        CompoundV3BorrowStorage storage $ = _getCompoundV3BorrowStorage();
        $._comet = IComet(comet_);
        $._borrowToken = borrowToken_;
        $._minBorrowLimit = 7_000; // 70% of actual collateral factor of protocol
        $._maxBorrowLimit = 8_500; // 85% of actual collateral factor of protocol
    }

    function borrowToken() public view returns (address) {
        return _getCompoundV3BorrowStorage()._borrowToken;
    }

    function comet() public view returns (IComet) {
        return _getCompoundV3BorrowStorage()._comet;
    }

    function isReservedToken(address token_) public view virtual override returns (bool) {
        return token_ == address(comet()) || token_ == address(collateralToken()) || token_ == borrowToken();
    }

    function maxBorrowLimit() public view returns (uint256) {
        return _getCompoundV3BorrowStorage()._maxBorrowLimit;
    }

    function minBorrowLimit() public view returns (uint256) {
        return _getCompoundV3BorrowStorage()._minBorrowLimit;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view override returns (uint256) {
        IERC20 _collateralToken = collateralToken();
        return
            comet().collateralBalanceOf(address(this), address(_collateralToken)) +
            _collateralToken.balanceOf(address(this));
    }

    /// @dev Hook that executes after collateral borrow.
    function _afterBorrowY(uint256 amount_) internal virtual {}

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

    /// @dev Borrow Y from Compound. _afterBorrowY hook can be used to do anything with borrowed amount.
    /// @dev Override to handle ETH
    function _borrowY(uint256 amount_) internal virtual {
        if (amount_ > 0) {
            comet().withdraw(borrowToken(), amount_);
            _afterBorrowY(amount_);
        }
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
    ) internal view returns (uint256 _borrowAmount, uint256 _repayAmount) {
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

    /// @dev Deposit collateral in Compound V3 and adjust borrow position
    function _deposit() internal {
        IERC20 _collateralToken = collateralToken();
        uint256 _collateralBalance = _collateralToken.balanceOf(address(this));
        (uint256 _borrowAmount, uint256 _repayAmount) = _calculateBorrowPosition(_collateralBalance, 0);
        if (_repayAmount > 0) {
            // Repay to maintain safe position
            _repay(_repayAmount);
            _mintX(_collateralToken.balanceOf(address(this)));
        } else {
            // Happy path, mint more borrow more
            _mintX(_collateralBalance);
            _borrowY(_borrowAmount);
        }
    }

    function _getAvailableLiquidity() internal view virtual returns (uint256) {
        IComet _comet = comet();
        uint256 _totalSupply = _comet.totalSupply();
        uint256 _totalBorrow = _comet.totalBorrow();
        return _totalSupply > _totalBorrow ? _totalSupply - _totalBorrow : 0;
    }

    function _getYTokensInProtocol() internal view virtual returns (uint256) {}

    /// @dev Deposit collateral aka X in Compound. Override to handle ETH
    function _mintX(uint256 amount_) internal virtual {
        if (amount_ > 0) {
            comet().supply(address(collateralToken()), amount_);
        }
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        IComet _comet = comet();
        {
            address _borrowToken = borrowToken();
            uint256 _yTokensBorrowed = _comet.borrowBalanceOf(address(this));
            uint256 _yTokensHere = IERC20(_borrowToken).balanceOf(address(this));
            uint256 _yTokensInProtocol = _getYTokensInProtocol();
            uint256 _totalYTokens = _yTokensHere + _yTokensInProtocol;

            // _borrow increases every block. Convert collateral to borrowToken.
            if (_yTokensBorrowed > _totalYTokens) {
                _swapToBorrowToken(_yTokensBorrowed - _totalYTokens);
            } else {
                // When _yTokensInProtocol exceeds _yTokensBorrowed from Compound
                // then we have profit from investing borrow tokens. _yTokensHere is profit.
                if (_yTokensInProtocol > _yTokensBorrowed) {
                    _withdrawY(_yTokensInProtocol - _yTokensBorrowed);
                    _yTokensHere = IERC20(_borrowToken).balanceOf(address(this));
                }
                if (_yTokensHere > 0) {
                    _trySwapExactInput(_borrowToken, address(_collateralToken), _yTokensHere);
                }
            }
        }

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
        _pool.reportEarning(_profit, _loss, _payback);

        _deposit();
    }

    /**
     * @dev Repay borrow amount
     * @dev Swap collateral to borrowToken as needed.
     * @param repayAmount_ BorrowToken amount that we should repay to maintain safe position.
     */
    function _repay(uint256 repayAmount_) internal {
        if (repayAmount_ > 0) {
            uint256 _totalYTokens = IERC20(borrowToken()).balanceOf(address(this)) + _getYTokensInProtocol();
            // Liability is more than what we have.
            // To repay loan - convert all rewards to collateral, if asked, and redeem collateral(if needed).
            // This scenario is rare and if system works okay it will/might happen during final repay only.
            if (repayAmount_ > _totalYTokens) {
                uint256 _yTokensBorrowed = comet().borrowBalanceOf(address(this));
                // For example this is final repay and 100 blocks has passed since last withdraw/rebalance,
                // _yTokensBorrowed is increasing due to interest. Now if _repayAmount > _borrowBalanceHere is true
                // _yTokensBorrowed > _borrowBalanceHere is also true.
                // To maintain safe position we always try to keep _yTokensBorrowed = _borrowBalanceHere

                // Swap collateral to borrowToken to repay borrow and also maintain safe position
                // Here borrowToken amount needed is (_yTokensBorrowed - _borrowBalanceHere)
                _swapToBorrowToken(_yTokensBorrowed - _totalYTokens);
            }
            _repayY(repayAmount_);
        }
    }

    /// @dev Repay Y to Compound V3. Withdraw Y from end protocol if applicable.
    /// @dev Override this to handle ETH
    function _repayY(uint256 amount_) internal virtual {
        _withdrawY(amount_);
        comet().supply(borrowToken(), amount_);
    }

    /**
     * @dev Swap given token to borrowToken
     * @param shortOnBorrow_ Expected output of this swap
     */
    function _swapToBorrowToken(uint256 shortOnBorrow_) internal {
        // Looking for _amountIn using fixed output amount
        IERC20 _collateralToken = collateralToken();
        address _borrowToken = borrowToken();
        ISwapper _swapper = swapper();
        uint256 _amountIn = _swapper.getAmountIn(address(_collateralToken), _borrowToken, shortOnBorrow_);
        if (_amountIn > 0) {
            uint256 _collateralHere = _collateralToken.balanceOf(address(this));
            // If we do not have enough _from token to get expected output, either get
            // some _from token or adjust expected output.
            if (_amountIn > _collateralHere) {
                // Redeem some collateral, so that we have enough collateral to get expected output
                comet().withdraw(address(_collateralToken), _amountIn - _collateralHere);
            }
            _swapper.swapExactOutput(address(_collateralToken), _borrowToken, shortOnBorrow_, _amountIn, address(this));
        }
    }

    /// @dev Withdraw collateral here. Do not transfer to pool
    function _withdrawHere(uint256 amount_) internal override {
        (, uint256 _repayAmount) = _calculateBorrowPosition(0, amount_);
        _repay(_repayAmount);
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

    function _withdrawY(uint256 _amount) internal virtual {}

    /************************************************************************************************
     *                          Governor/admin/keeper function                                      *
     ***********************************************************************************************/
    /**
     * @notice Recover extra borrow tokens from strategy
     * @dev If we get liquidation in Compound, we will have borrowToken sitting in strategy.
     * This function allows to recover idle borrow token amount.
     * @param amountToRecover_ Amount of borrow token we want to recover in 1 call.
     *      Set it 0 to recover all available borrow tokens
     */
    function recoverBorrowToken(uint256 amountToRecover_) external onlyKeeper {
        IERC20 _collateralToken = collateralToken();
        address _borrowToken = borrowToken();
        uint256 _borrowBalanceHere = IERC20(_borrowToken).balanceOf(address(this));
        uint256 _borrowInCompound = comet().borrowBalanceOf(address(this));

        if (_borrowBalanceHere > _borrowInCompound) {
            uint256 _extraBorrowBalance = _borrowBalanceHere - _borrowInCompound;
            uint256 _recoveryAmount = (amountToRecover_ > 0 && _extraBorrowBalance > amountToRecover_)
                ? amountToRecover_
                : _extraBorrowBalance;
            // Do swap and transfer
            uint256 _amountOut = _trySwapExactInput(_borrowToken, address(_collateralToken), _recoveryAmount);
            if (_amountOut > 0) {
                _collateralToken.safeTransfer(pool(), _amountOut);
            }
        }
    }

    /**
     * @notice Repay all borrow amount and set min borrow limit to 0.
     * @dev This action usually done when loss is detected in strategy.
     * @dev 0 borrow limit make sure that any future rebalance do not borrow again.
     */
    function repayAll() external onlyKeeper {
        CompoundV3BorrowStorage storage $ = _getCompoundV3BorrowStorage();
        _repay($._comet.borrowBalanceOf(address(this)));
        $._minBorrowLimit = 0;
        $._maxBorrowLimit = 0;
    }

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
}
