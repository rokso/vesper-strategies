// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import "../Strategy.sol";
import "../../interfaces/extra-finance/ILendingPool.sol";
import "../../interfaces/extra-finance/IEToken.sol";
import "../../interfaces/extra-finance/IStakingRewards.sol";

/// @title This strategy will deposit collateral token in Extra Finance and earn interest.
contract ExtraFinance is Strategy {
    using SafeERC20 for IERC20;
    using SafeERC20 for IEToken;

    error InvalidReserve();
    error InvalidLendingPool();
    error SlippageTooHigh();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.ExtraFinance
    struct ExtraFinanceStorage {
        ILendingPool _lendingPool;
        IStakingRewards _staking;
        IEToken _eToken;
        uint256 _reserveId;
    }

    bytes32 private constant ExtraFinanceStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.ExtraFinance")) - 1)) & ~bytes32(uint256(0xff));

    function _getExtraFinanceStorage() internal pure returns (ExtraFinanceStorage storage $) {
        bytes32 _location = ExtraFinanceStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        ILendingPool lendingPool_,
        uint256 reserveId_,
        string memory name_
    ) external initializer {
        // init require non-zero value for receiptToken hence setting it to 0x1.
        // receiptToken is overridden in this contract to return eToken address
        __Strategy_init(pool_, swapper_, address(0x1), name_);

        if (address(lendingPool_) == address(0)) revert AddressIsNull();
        ExtraFinanceStorage storage $ = _getExtraFinanceStorage();
        $._lendingPool = lendingPool_;

        _setReserve(lendingPool_, reserveId_);
    }

    function eToken() public view returns (IEToken) {
        return _getExtraFinanceStorage()._eToken;
    }

    /// @dev override receiptToken as eToken can be updated via migrateReserve function
    function receiptToken() public view virtual override returns (address) {
        return address(eToken());
    }

    /// @inheritdoc Strategy
    function isReservedToken(address token_) public view virtual override returns (bool) {
        return token_ == receiptToken();
    }

    function lendingPool() public view returns (ILendingPool) {
        return _getExtraFinanceStorage()._lendingPool;
    }

    function reserveId() public view returns (uint256) {
        return _getExtraFinanceStorage()._reserveId;
    }

    function staking() public view returns (IStakingRewards) {
        return _getExtraFinanceStorage()._staking;
    }

    /// @inheritdoc Strategy
    function tvl() external view override returns (uint256) {
        return collateralToken().balanceOf(address(this)) + _invested();
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        ExtraFinanceStorage storage $ = _getExtraFinanceStorage();
        address _lendingPool = address($._lendingPool);
        IERC20 _eToken = $._eToken;
        address _staking = address($._staking);

        IERC20 _collateralToken = collateralToken();
        _collateralToken.forceApprove(pool(), amount_);
        _collateralToken.forceApprove(_lendingPool, amount_);

        _eToken.forceApprove(_staking, amount_);
        _eToken.forceApprove(_lendingPool, amount_);
    }

    /// @inheritdoc Strategy
    function _claimRewards() internal override {
        staking().claim();
    }

    /// @dev Convert eToken amount to collateral amount
    function _convertToCollateral(uint256 eTokenAmount_) private view returns (uint256 _collateralAmount) {
        return (eTokenAmount_ * lendingPool().exchangeRateOfReserve(reserveId())) / 1e18;
    }

    /// @dev Convert collateral amount to eToken amount
    function _convertToReceiptToken(uint256 collateralAmount_) private view returns (uint256 _eTokenAmount) {
        return (collateralAmount_ * 1e18) / lendingPool().exchangeRateOfReserve(reserveId());
    }

    /// @dev Deposit collateral and stake the received eTokens
    function _deposit(uint256 amount_) internal virtual {
        if (amount_ > 0) {
            lendingPool().deposit(reserveId(), amount_, address(this), 0);
            uint256 _eTokenBalance = eToken().balanceOf(address(this));
            if (_eTokenBalance > 0) {
                staking().stake(_eTokenBalance, address(this)); // stake all
            }
        }
    }

    /// @dev Total collateral amount allocated
    function _invested() private view returns (uint256) {
        return _convertToCollateral(eToken().balanceOf(address(this)) + staking().balanceOf(address(this)));
    }

    /// @dev Generate report for pools accounting and also send profit and any payback to pool.
    function _rebalance() internal virtual override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _collateralHere + _invested();
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

        // After reportEarning strategy may get more collateral from pool. Deposit those in ExtraFinance.
        _deposit(_collateralToken.balanceOf(address(this)));
    }

    /// @dev set reserve params of protocol
    function _setReserve(ILendingPool lendingPool_, uint256 reserveId_) private {
        if (lendingPool_.getUnderlyingTokenAddress(reserveId_) != address(collateralToken())) revert InvalidReserve();

        IEToken _eToken = IEToken(lendingPool_.getETokenAddress(reserveId_));
        if (address(_eToken) == address(0)) revert AddressIsNull();
        if (_eToken.lendingPool() != address(lendingPool_)) revert InvalidLendingPool();

        IStakingRewards _staking = IStakingRewards(lendingPool_.getStakingAddress(reserveId_));
        if (address(_staking) == address(0)) revert AddressIsNull();

        ExtraFinanceStorage storage $ = _getExtraFinanceStorage();
        $._reserveId = reserveId_;
        $._eToken = _eToken;
        $._staking = _staking;
    }

    function _unstakeAll() private {
        IStakingRewards _staking = staking();
        uint256 _staked = _staking.balanceOf(address(this));
        if (_staked > 0) {
            _staking.withdraw(_staked, address(this));
        }
    }

    /// @dev Withdraw collateral here. Do not transfer to pool
    function _withdrawHere(uint256 collateralAmount_) internal override {
        // Get minimum of requested amount and available collateral
        collateralAmount_ = Math.min(
            collateralAmount_,
            Math.min(_invested(), collateralToken().balanceOf(address(eToken())))
        );

        uint256 _eTokenAmount = _convertToReceiptToken(collateralAmount_);
        uint256 _eTokenBalance = eToken().balanceOf(address(this));

        if (_eTokenAmount > _eTokenBalance) {
            uint256 _unstakeAmount = _eTokenAmount - _eTokenBalance;
            staking().withdraw(_unstakeAmount, address(this));
            _eTokenBalance = eToken().balanceOf(address(this));
        }

        if (_eTokenAmount > 0) {
            lendingPool().redeem(reserveId(), Math.min(_eTokenAmount, _eTokenBalance), address(this), false);
        }
    }

    /************************************************************************************************
     *                          Governor/admin/keeper function                                      *
     ***********************************************************************************************/

    /// @notice Migrate funds to another reserve that supports' the same collateral
    function migrateReserve(uint256 newReserveId_) external onlyGovernor {
        // 1. Claim rewards from current staking contract
        IERC20 _collateralToken = collateralToken();
        _claimRewards();

        // 2. Withdraw all collateral
        // Note: Do not use `_withdrawHere` in order to make it reverts if available liquidity isn't enough
        _unstakeAll();
        ILendingPool _lendingPool = lendingPool();
        _lendingPool.redeem(reserveId(), eToken().balanceOf(address(this)), address(this), false);

        // 3. Setup the new reserve
        _setReserve(_lendingPool, newReserveId_);

        // 4. Setup required approvals
        _approveToken(MAX_UINT_VALUE);

        // 5. Deposit all collateral to the new reserve
        _deposit(_collateralToken.balanceOf(address(this)));
    }
}
