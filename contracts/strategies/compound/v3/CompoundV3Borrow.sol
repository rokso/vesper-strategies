// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BorrowStrategy} from "../../BorrowStrategy.sol";
import {IComet} from "../../../interfaces/compound/IComet.sol";
import {IRewards} from "../../../interfaces/compound/IRewards.sol";

// solhint-disable no-empty-blocks

/// @title This is base strategy for CompoundV3 borrow.
/// This strategy will deposit collateral token in Compound V3 and based on position it will
/// borrow based token. Supply X borrow Y and keep borrowed amount here.
abstract contract CompoundV3Borrow is BorrowStrategy {
    using SafeERC20 for IERC20;

    error BorrowTokenMismatch();
    error PriceError();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.CompoundV3Borrow
    struct CompoundV3BorrowStorage {
        IRewards _compRewards;
        address _rewardToken;
        IComet _comet;
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
        address compRewards_,
        address rewardToken_,
        address comet_,
        address borrowToken_,
        string memory name_
    ) internal onlyInitializing {
        __Borrow_init(pool_, swapper_, comet_, borrowToken_, name_);
        if (compRewards_ == address(0) || rewardToken_ == address(0)) revert AddressIsNull();
        if (IComet(comet_).baseToken() != borrowToken_) revert BorrowTokenMismatch();

        CompoundV3BorrowStorage storage $ = _getCompoundV3BorrowStorage();
        $._comet = IComet(comet_);
        $._compRewards = IRewards(compRewards_);
        $._rewardToken = rewardToken_;
    }

    function comet() public view returns (IComet) {
        return _getCompoundV3BorrowStorage()._comet;
    }

    function compRewards() public view returns (IRewards) {
        return _getCompoundV3BorrowStorage()._compRewards;
    }

    function rewardToken() public view returns (address) {
        return _getCompoundV3BorrowStorage()._rewardToken;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view override returns (uint256) {
        return _getSupplied() + collateralToken().balanceOf(address(this));
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
        IERC20(rewardToken()).forceApprove(_swapper, amount_);
    }

    /// @dev Borrow tokens from Compound.
    function _borrow(uint256 borrowAmount_) internal override {
        comet().withdraw(borrowToken(), borrowAmount_);
    }

    /// @dev Claim COMP
    function _claimRewards() internal override returns (address, uint256) {
        CompoundV3BorrowStorage memory s = _getCompoundV3BorrowStorage();
        address _rewardToken = address(s._rewardToken);

        s._compRewards.claim(address(s._comet), address(this), true);
        return (_rewardToken, IERC20(_rewardToken).balanceOf(address(this)));
    }

    function _calculateBorrowPosition(
        uint256 amount_,
        bool isDeposit_
    ) internal view override returns (uint256 _borrowAmount, uint256 _repayAmount) {
        IComet _comet = comet();
        address _collateralToken = address(collateralToken());
        uint256 _borrowed = _comet.borrowBalanceOf(address(this));
        // If maximum borrow limit set to 0 then repay borrow
        if (maxBorrowLimit() == 0) {
            return (0, _borrowed);
        }

        uint256 _collateralSupplied = _comet.collateralBalanceOf(address(this), _collateralToken);

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

    /// @dev Deposit collateral in Compound.
    function _depositCollateral(uint256 amount_) internal override {
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

    function _getBorrowed() internal view override returns (uint256) {
        return comet().borrowBalanceOf(address(this));
    }

    function _getPriceFeed(IComet comet_, address token_) private view returns (address) {
        return token_ == borrowToken() ? comet_.baseTokenPriceFeed() : comet_.getAssetInfoByAddress(token_).priceFeed;
    }

    function _getSupplied() internal view override returns (uint256) {
        return comet().collateralBalanceOf(address(this), address(collateralToken()));
    }

    function _quote(address tokenIn_, address tokenOut_, uint256 amountIn_) internal view override returns (uint256) {
        IComet _comet = comet();
        uint256 _tokenInPrice = _comet.getPrice(_getPriceFeed(_comet, tokenIn_));
        uint256 _tokenOutPrice = _comet.getPrice(_getPriceFeed(_comet, tokenOut_));

        if (_tokenInPrice == 0 || _tokenOutPrice == 0) revert PriceError();
        return ((_tokenInPrice * amountIn_ * (10 ** IERC20Metadata(tokenOut_).decimals())) /
            (10 ** IERC20Metadata(tokenIn_).decimals() * _tokenOutPrice));
    }

    /// @dev Repay borrow tokens to Compound.
    function _repay(uint256 repayAmount_) internal override {
        comet().supply(borrowToken(), repayAmount_);
    }

    function _withdrawCollateral(uint256 amount_) internal override {
        comet().withdraw(address(collateralToken()), amount_);
    }

    function _withdrawHere(uint256 amount_) internal override {
        // Adjust position based on withdrawal of amount_.
        // Setting false for withdraw
        _adjustBorrowPosition(amount_, false);

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
}
