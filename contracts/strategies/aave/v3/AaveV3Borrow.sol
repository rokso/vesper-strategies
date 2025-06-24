// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAToken} from "../../../interfaces/aave/IAToken.sol";
import {ILendingPool} from "../../../interfaces/aave/ILendingPool.sol";
import {IAaveOracle} from "../../../interfaces/aave/IAaveOracle.sol";
import {IPoolAddressesProvider} from "../../../interfaces/aave/IPoolAddressesProvider.sol";
import {BorrowStrategy} from "../../BorrowStrategy.sol";
import {AaveV3Incentive} from "./AaveV3Incentive.sol";

/// @title Deposit Collateral in Aave and earn interest by depositing borrowed token in a Vesper Pool.
abstract contract AaveV3Borrow is BorrowStrategy {
    using SafeERC20 for IERC20;

    error DepositFailed(string reason);
    error IncorrectWithdrawAmount();
    error InvalidInput();
    error CollateralTokenMismatch();
    error PriceError();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.AaveV3Borrow
    struct AaveV3BorrowStorage {
        IPoolAddressesProvider _poolAddressesProvider;
        IAToken _vdToken; // variable debt token
        address _aBorrowToken;
    }

    bytes32 private constant AaveV3BorrowStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.AaveV3Borrow")) - 1)) & ~bytes32(uint256(0xff));

    function _getAaveV3BorrowStorage() private pure returns (AaveV3BorrowStorage storage $) {
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
    ) internal onlyInitializing {
        __Borrow_init(pool_, swapper_, receiptToken_, borrowToken_, name_);
        if (poolAddressesProvider_ == address(0)) revert AddressIsNull();
        if (IAToken(receiptToken_).UNDERLYING_ASSET_ADDRESS() != address(collateralToken()))
            revert CollateralTokenMismatch();

        (address _aBorrowToken, , address _vdToken) = IPoolAddressesProvider(poolAddressesProvider_)
            .getPoolDataProvider()
            .getReserveTokensAddresses(borrowToken_);

        AaveV3BorrowStorage storage $ = _getAaveV3BorrowStorage();
        $._poolAddressesProvider = IPoolAddressesProvider(poolAddressesProvider_);
        $._vdToken = IAToken(_vdToken);
        $._aBorrowToken = _aBorrowToken;
    }

    function aavePoolAddressesProvider() public view returns (IPoolAddressesProvider) {
        return _getAaveV3BorrowStorage()._poolAddressesProvider;
    }

    function aavePool() public view returns (ILendingPool) {
        return aavePoolAddressesProvider().getPool();
    }

    function aBorrowToken() public view returns (address) {
        return _getAaveV3BorrowStorage()._aBorrowToken;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view virtual override returns (uint256) {
        // receiptToken is aToken. aToken is 1:1 of collateral token
        return IERC20(receiptToken()).balanceOf(address(this)) + collateralToken().balanceOf(address(this));
    }

    function vdToken() public view returns (IAToken) {
        return _getAaveV3BorrowStorage()._vdToken;
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        address _swapper = address(swapper());
        IERC20 _collateralToken = collateralToken();
        IERC20 _borrowToken = IERC20(borrowToken());
        address _lendingPool = address(aavePool());
        _collateralToken.forceApprove(_lendingPool, amount_);
        _collateralToken.forceApprove(_swapper, amount_);
        _borrowToken.forceApprove(_lendingPool, amount_);
        _borrowToken.forceApprove(_swapper, amount_);
    }

    /// @dev Borrow tokens from Aave.
    function _borrow(uint256 borrowAmount_) internal override {
        // using 2 for variable rate borrow, 0 for referralCode
        aavePool().borrow(borrowToken(), borrowAmount_, 2, 0, address(this));
    }

    function _calculateBorrowPosition(
        uint256 amount_,
        bool isDeposit_
    ) internal view override returns (uint256 _borrowAmount, uint256 _repayAmount) {
        uint256 _borrowed = vdToken().balanceOf(address(this));
        // If maximum borrow limit set to 0 then repay borrow
        if (maxBorrowLimit() == 0) {
            return (0, _borrowed);
        }

        uint256 _supplied = _getSupplied();
        // In case of withdraw, amount_ may be greater than _supplied
        uint256 _hypotheticalCollateral;
        if (isDeposit_) {
            _hypotheticalCollateral = _supplied + amount_;
        } else if (!isDeposit_ && _supplied > amount_) {
            _hypotheticalCollateral = _supplied - amount_;
        }
        if (_hypotheticalCollateral == 0) {
            return (0, _borrowed);
        }

        IAaveOracle _aaveOracle = aavePoolAddressesProvider().getPriceOracle();
        address _borrowToken = borrowToken();
        address _collateralToken = address(collateralToken());
        uint256 _borrowTokenPrice = _aaveOracle.getAssetPrice(_borrowToken);
        uint256 _collateralTokenPrice = _aaveOracle.getAssetPrice(_collateralToken);
        if (_borrowTokenPrice == 0 || _collateralTokenPrice == 0) {
            // Oracle problem. Lets payback all
            return (0, _borrowed);
        }
        // _collateralFactor in 4 decimal. 10_000 = 100%
        (, uint256 _collateralFactor, , , , , , , , ) = aavePoolAddressesProvider()
            .getPoolDataProvider()
            .getReserveConfigurationData(_collateralToken);

        // Collateral in base currency based on oracle price and cf;
        uint256 _actualCollateralForBorrow = (_hypotheticalCollateral * _collateralFactor * _collateralTokenPrice) /
            (MAX_BPS * (10 ** IERC20Metadata(_collateralToken).decimals()));
        // Calculate max borrow possible in borrow token number
        uint256 _maxBorrowPossible = (_actualCollateralForBorrow * (10 ** IERC20Metadata(_borrowToken).decimals())) /
            _borrowTokenPrice;
        if (_maxBorrowPossible == 0) {
            return (0, _borrowed);
        }
        // Safe buffer to avoid liquidation due to price variations.
        uint256 _borrowUpperBound = (_maxBorrowPossible * maxBorrowLimit()) / MAX_BPS;

        // Borrow up to _borrowLowerBound and keep buffer of _borrowUpperBound - _borrowLowerBound for price variation
        uint256 _borrowLowerBound = (_maxBorrowPossible * minBorrowLimit()) / MAX_BPS;

        // If current borrow is greater than max borrow, then repay to achieve safe position.
        if (_borrowed > _borrowUpperBound) {
            // If borrow > upperBound then it is greater than lowerBound too.
            _repayAmount = _borrowed - _borrowLowerBound;
        } else if (_borrowLowerBound > _borrowed) {
            _borrowAmount = _borrowLowerBound - _borrowed;
            uint256 _availableLiquidity = IERC20(_borrowToken).balanceOf(aBorrowToken());
            if (_borrowAmount > _availableLiquidity) {
                _borrowAmount = _availableLiquidity;
            }
        }
    }

    /// @dev Claim all rewards and convert to collateral.
    /// Overriding _claimAndSwapRewards will help child contract otherwise override _claimReward.
    function _claimAndSwapRewards() internal virtual override {
        (address[] memory _tokens, uint256[] memory _amounts) = AaveV3Incentive._claimRewards(receiptToken());
        address _collateralToken = address(collateralToken());
        address _borrowToken = borrowToken();
        address _swapper = address(swapper());
        uint256 _length = _tokens.length;
        for (uint256 i; i < _length; ++i) {
            if (_amounts[i] > 0 && _tokens[i] != _collateralToken) {
                // borrow token already has approval
                if (_tokens[i] != _borrowToken) {
                    IERC20(_tokens[i]).forceApprove(_swapper, _amounts[i]);
                }
                _trySwapExactInput(_tokens[i], _collateralToken, _amounts[i]);
            }
        }
    }

    function _depositCollateral(uint256 amount_) internal override {
        if (amount_ > 0) {
            // solhint-disable-next-line no-empty-blocks
            try aavePool().supply(address(collateralToken()), amount_, address(this), 0) {} catch Error(
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

    function _getBorrowed() internal view override returns (uint256) {
        return vdToken().balanceOf(address(this));
    }

    function _getSupplied() internal view override returns (uint256) {
        return IERC20(receiptToken()).balanceOf(address(this));
    }

    function _quote(address tokenIn_, address tokenOut_, uint256 amountIn_) internal view override returns (uint256) {
        IAaveOracle _aaveOracle = aavePoolAddressesProvider().getPriceOracle();
        uint256 _tokenInPrice = _aaveOracle.getAssetPrice(tokenIn_);
        uint256 _tokenOutPrice = _aaveOracle.getAssetPrice(tokenOut_);

        if (_tokenInPrice == 0 || _tokenOutPrice == 0) revert PriceError();
        return ((_tokenInPrice * amountIn_ * (10 ** IERC20Metadata(tokenOut_).decimals())) /
            (10 ** IERC20Metadata(tokenIn_).decimals() * _tokenOutPrice));
    }

    /// @dev Repay borrow tokens to Aave.
    function _repay(uint256 repayAmount_) internal override {
        aavePool().repay(borrowToken(), repayAmount_, 2, address(this));
    }

    function _withdrawCollateral(uint256 amount_) internal override {
        if (aavePool().withdraw(address(collateralToken()), amount_, address(this)) != amount_)
            revert IncorrectWithdrawAmount();
    }

    function _withdrawHere(uint256 amount_) internal virtual override {
        // Adjust position based on withdrawal of amount_.
        // Setting false for withdraw
        _adjustBorrowPosition(amount_, false);

        IERC20 _collateralToken = collateralToken();
        address _receiptToken = receiptToken();
        // Get minimum of amount_ and collateral supplied and available liquidity of collateral
        uint256 _withdrawAmount = Math.min(
            amount_,
            Math.min(IERC20(_receiptToken).balanceOf(address(this)), _collateralToken.balanceOf(_receiptToken))
        );
        if (aavePool().withdraw(address(_collateralToken), _withdrawAmount, address(this)) != _withdrawAmount)
            revert IncorrectWithdrawAmount();
    }
}
