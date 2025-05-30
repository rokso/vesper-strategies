// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAToken} from "../../../interfaces/aave/IAToken.sol";
import {IPoolAddressesProvider} from "../../../interfaces/aave/IPoolAddressesProvider.sol";
import {IVesperPool} from "../../../interfaces/vesper/IVesperPool.sol";
import {Strategy} from "../../Strategy.sol";
import {AaveV3Incentive} from "./AaveV3Incentive.sol";

/// @dev This strategy will deposit collateral token in Aave and earn interest.
contract AaveV3 is Strategy {
    using SafeERC20 for IERC20;

    error IncorrectWithdrawAmount();
    error InvalidReceiptToken();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.AaveV3
    struct AaveV3Storage {
        IPoolAddressesProvider _poolAddressesProvider;
    }

    bytes32 private constant AaveV3StorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.AaveV3")) - 1)) & ~bytes32(uint256(0xff));

    function _getAaveV3Storage() internal pure returns (AaveV3Storage storage $) {
        bytes32 _location = AaveV3StorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        address poolAddressesProvider_,
        string memory name_
    ) external initializer {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);

        if (poolAddressesProvider_ == address(0)) revert AddressIsNull();
        if (IAToken(receiptToken_).UNDERLYING_ASSET_ADDRESS() != address(IVesperPool(pool_).token()))
            revert InvalidReceiptToken();
        _getAaveV3Storage()._poolAddressesProvider = IPoolAddressesProvider(poolAddressesProvider_);
    }

    function aavePoolAddressesProvider() public view returns (IPoolAddressesProvider) {
        return _getAaveV3Storage()._poolAddressesProvider;
    }

    /**
     * @notice Report total value locked in this strategy
     * @dev aToken and collateral are 1:1
     */
    function tvl() public view override returns (uint256 _tvl) {
        // receiptToken is aToken
        _tvl = IERC20(receiptToken()).balanceOf(address(this)) + collateralToken().balanceOf(address(this));
    }

    /// @notice Large approval of token
    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        collateralToken().forceApprove(address(aavePoolAddressesProvider().getPool()), amount_);
    }

    /// @dev Claim all rewards and convert to collateral.
    function _claimAndSwapRewards() internal override {
        (address[] memory _tokens, uint256[] memory _amounts) = AaveV3Incentive._claimRewards(receiptToken());
        address _collateralToken = address(collateralToken());
        address _swapper = address(swapper());
        uint256 _length = _tokens.length;
        for (uint256 i; i < _length; ++i) {
            if (_amounts[i] > 0 && _tokens[i] != _collateralToken) {
                IERC20(_tokens[i]).forceApprove(_swapper, _amounts[i]);
                _trySwapExactInput(_tokens[i], _collateralToken, _amounts[i]);
            }
        }
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));

        uint256 _totalCollateral = IERC20((receiptToken())).balanceOf(address(this)) + _collateralHere;

        if (_totalCollateral > _totalDebt) {
            _profit = _totalCollateral - _totalDebt;
        } else {
            _loss = _totalDebt - _totalCollateral;
        }
        uint256 _profitAndExcessDebt = _profit + _excessDebt;
        if (_profitAndExcessDebt > _collateralHere) {
            _withdrawHere(_profitAndExcessDebt - _collateralHere);
            _collateralHere = _collateralToken.balanceOf(address(this));
        }

        // Make sure _collateralHere >= _payback + profit. set actual payback first and then profit
        _payback = Math.min(_collateralHere, _excessDebt);
        _profit = _collateralHere > _payback ? Math.min((_collateralHere - _payback), _profit) : 0;
        _pool.reportEarning(_profit, _loss, _payback);

        // strategy may get new fund. deposit to generate yield
        _collateralHere = _collateralToken.balanceOf(address(this));
        if (_collateralHere > 0) {
            aavePoolAddressesProvider().getPool().supply(address(_collateralToken), _collateralHere, address(this), 0);
        }
    }

    /// @dev Withdraw collateral here. Do not transfer to pool
    function _withdrawHere(uint256 requireAmount_) internal override {
        IERC20 _collateralToken = collateralToken();
        address _receiptToken = receiptToken();
        // withdraw asking more than available liquidity will fail. To do safe withdraw, check
        // requireAmount_ against available liquidity.
        uint256 _possibleWithdraw = Math.min(
            requireAmount_,
            Math.min(IERC20(_receiptToken).balanceOf(address(this)), _collateralToken.balanceOf(_receiptToken))
        );
        if (_possibleWithdraw > 0) {
            if (
                aavePoolAddressesProvider().getPool().withdraw(
                    address(_collateralToken),
                    _possibleWithdraw,
                    address(this)
                ) != _possibleWithdraw
            ) revert IncorrectWithdrawAmount();
        }
    }
}
