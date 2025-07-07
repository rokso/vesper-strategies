// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../Strategy.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {IMasterOracle} from "../../interfaces/one-oracle/IMasterOracle.sol";
import {IAddressProvider} from "../../interfaces/curve/IAddressProvider.sol";
import {IDepositAndStake, IWithdraw} from "../../interfaces/curve/ICurve.sol";
import {ILiquidityGaugeV2} from "../../interfaces/curve/ILiquidityGauge.sol";
import {ILiquidityGaugeFactory} from "../../interfaces/curve/ILiquidityGaugeFactory.sol";
import {IMetaRegistry} from "../../interfaces/curve/IMetaRegistry.sol";
import {ITokenMinter} from "../../interfaces/curve/ITokenMinter.sol";

/// @title Base contract for Curve-related strategies
abstract contract CurveBase is Strategy {
    using SafeERC20 for IERC20;

    error CurveGaugeIsNull();
    error CurveLpIsNull();
    error CurvePoolZapIsNull();
    error InvalidCollateral();
    error InvalidSlippage();
    error MaxFourCoinsAreAllowed();
    error NotAllowedToSendEther();
    error OnlyOneEthAllowedInUnderlying();
    error SlippageTooHigh();

    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event MasterOracleUpdated(IMasterOracle oldMasterOracle, IMasterOracle newMasterOracle);

    ITokenMinter internal constant CRV_MINTER = ITokenMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0); // This contract only exists on ethereum
    ILiquidityGaugeFactory public constant GAUGE_FACTORY =
        ILiquidityGaugeFactory(0xabC000d88f23Bb45525E447528DBF656A9D55bf5); // Act as CRV_MINTER on side chains
    IAddressProvider public constant ADDRESS_PROVIDER = IAddressProvider(0x5ffe7FB82894076ECB99A30D6A32e969e6e35E98); // Same address to all chains
    uint256 private constant META_REGISTRY_ADDRESS_ID = 7;
    uint256 private constant MAX_BPS = 10_000;

    // Initialize params. Using this struct to mitigate stack too deep error.
    // It is being used during initialize only.
    struct CurveInitParams {
        address pool;
        address swapper;
        address curvePool;
        address curvePoolZap;
        address curveToken;
        address depositAndStake;
        bool useDynamicArray;
        uint256 slippage;
        address weth;
        address masterOracle;
        string name;
    }

    /// @custom:storage-location erc7201:vesper.storage.Strategy.CurveBase
    struct CurveBaseStorage {
        address _curveToken;
        address _curvePool;
        IERC20 _curveLp;
        ILiquidityGaugeV2 _curveGauge;
        address _curvePoolZap;
        address _depositAndStake;
        IWETH _weth;
        IMasterOracle _masterOracle;
        address _depositContract;
        address _curvePoolForDeposit;
        uint256 _slippage;
        int128 _collateralIdx;
        address[] _underlyingTokens;
        address[] _rewardTokens;
        bool _useDynamicArray;
        bool _useUnderlying;
    }

    bytes32 private constant CurveBaseStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.CurveBase")) - 1)) & ~bytes32(uint256(0xff));

    function _getCurveBaseStorage() internal pure returns (CurveBaseStorage storage $) {
        bytes32 _location = CurveBaseStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function __CurveBase_init(CurveInitParams memory params_) internal onlyInitializing {
        // init require non-zero value for receiptToken hence setting it to 0x1.
        // receiptToken is overridden in this contract to return curveLp address as receiptToken
        __Strategy_init(params_.pool, params_.swapper, address(0x1), params_.name);

        if (
            params_.curveToken == address(0) ||
            params_.curvePool == address(0) ||
            params_.depositAndStake == address(0) ||
            params_.weth == address(0) ||
            params_.masterOracle == address(0)
        ) revert AddressIsNull();

        IMetaRegistry _registry = IMetaRegistry(ADDRESS_PROVIDER.get_address(META_REGISTRY_ADDRESS_ID));

        address _curveLp = _registry.get_lp_token(params_.curvePool);
        if (_curveLp == address(0)) revert CurveLpIsNull();

        address _curveGauge = _registry.get_gauge(params_.curvePool);
        if (_curveGauge == address(0)) revert CurveGaugeIsNull();

        CurveBaseStorage storage $ = _getCurveBaseStorage();
        bool _isLendingTokenPool;
        bool _isMetaPool;
        ($._underlyingTokens, $._collateralIdx, _isMetaPool, _isLendingTokenPool) = _getCurvePoolInfo(
            _registry,
            params_.curvePool,
            params_.weth
        );
        $._curveToken = params_.curveToken;
        $._curvePool = params_.curvePool;
        $._curveLp = IERC20(_curveLp);
        $._curveGauge = ILiquidityGaugeV2(_curveGauge);
        $._curvePoolZap = params_.curvePoolZap;
        $._depositAndStake = params_.depositAndStake;
        $._weth = IWETH(params_.weth);
        $._masterOracle = IMasterOracle(params_.masterOracle);
        $._slippage = params_.slippage;
        $._useDynamicArray = params_.useDynamicArray;

        if (_isMetaPool) {
            if (params_.curvePoolZap == address(0)) revert CurvePoolZapIsNull();
            $._depositContract = params_.curvePoolZap;
            $._curvePoolForDeposit = params_.curvePool;
        } else {
            $._depositContract = params_.curvePool;
        }

        if (_isLendingTokenPool && params_.curvePoolZap != address(0)) {
            $._depositContract = params_.curvePoolZap;
            // useUnderlying is false in this case and false is default to no need to set.
        } else {
            // otherwise set useUnderlying
            $._useUnderlying = _isLendingTokenPool;
        }
    }

    receive() external payable {
        CurveBaseStorage memory s = _getCurveBaseStorage();
        address _curvePool = s._curvePool;
        IWETH _weth = s._weth;
        if (msg.sender != _curvePool && msg.sender != address(_weth)) revert NotAllowedToSendEther();
        if (msg.sender == _curvePool) {
            _weth.deposit{value: address(this).balance}();
        }
    }

    function curveToken() public view returns (address) {
        return _getCurveBaseStorage()._curveToken;
    }

    function curvePool() public view returns (address) {
        return _getCurveBaseStorage()._curvePool;
    }

    function curveLp() public view returns (IERC20) {
        return _getCurveBaseStorage()._curveLp;
    }

    function curveGauge() public view returns (ILiquidityGaugeV2) {
        return _getCurveBaseStorage()._curveGauge;
    }

    function curvePoolZap() public view returns (address) {
        return _getCurveBaseStorage()._curvePoolZap;
    }

    function depositAndStake() public view returns (address) {
        return _getCurveBaseStorage()._depositAndStake;
    }

    function getRewardTokens() public view returns (address[] memory) {
        return _getCurveBaseStorage()._rewardTokens;
    }

    function getUnderlyingTokens() public view returns (address[] memory) {
        return _getCurveBaseStorage()._underlyingTokens;
    }

    // Gets LP value not staked in gauge
    function lpBalanceHere() public view returns (uint256 _lpHere) {
        _lpHere = curveLp().balanceOf(address(this));
    }

    function lpBalanceHereAndStaked() public view returns (uint256 _lpHereAndStaked) {
        _lpHereAndStaked = curveLp().balanceOf(address(this)) + lpBalanceStaked();
    }

    function lpBalanceStaked() public view virtual returns (uint256 _lpStaked) {
        _lpStaked = curveGauge().balanceOf(address(this));
    }

    function masterOracle() public view returns (IMasterOracle) {
        return _getCurveBaseStorage()._masterOracle;
    }

    function receiptToken() public view override returns (address) {
        return address(curveLp());
    }

    function slippage() public view returns (uint256) {
        return _getCurveBaseStorage()._slippage;
    }

    /// @notice Returns collateral balance + collateral deposited to curve
    function tvl() external view override returns (uint256) {
        return collateralToken().balanceOf(address(this)) + _quoteLpToCollateral(lpBalanceHereAndStaked());
    }

    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);

        CurveBaseStorage memory s = _getCurveBaseStorage();
        if (s._curvePoolZap != address(0)) {
            // It is needed for withdrawal
            s._curveLp.forceApprove(s._curvePoolZap, amount_);
        }

        address _swapper = address(swapper());
        address[] memory _underlyingTokens = s._underlyingTokens;
        uint256 _nCoins = _underlyingTokens.length;
        for (uint256 i; i < _nCoins; i++) {
            address _underlyingToken = _underlyingTokens[i];
            IERC20(_underlyingToken).forceApprove(_swapper, amount_);
            IERC20(_underlyingToken).forceApprove(s._depositAndStake, amount_);
        }

        address[] memory _rewardTokens = s._rewardTokens;
        uint256 _rewardTokensLength = _rewardTokens.length;
        for (uint256 i; i < _rewardTokensLength; ++i) {
            IERC20(_rewardTokens[i]).forceApprove(_swapper, amount_);
        }

        // Gauge needs to be approved for stake via depositAndStake contract. Some Gauge doesn't support this method
        try ILiquidityGaugeV2(s._curveGauge).set_approve_deposit(s._depositAndStake, true) {} catch {}
    }

    /**
     * @dev Curve pool may have more than one reward token.
     */
    function _claimAndSwapRewards() internal override {
        _claimRewards();
        address _collateralToken = address(collateralToken());
        address[] memory _rewardTokens = getRewardTokens();
        uint256 _len = _rewardTokens.length;
        for (uint256 i; i < _len; ++i) {
            address _rewardToken = _rewardTokens[i];
            uint256 _amountIn = IERC20(_rewardToken).balanceOf(address(this));
            if (_amountIn > 0) {
                _trySwapExactInput(_rewardToken, _collateralToken, _amountIn);
            }
        }
    }

    /// @dev Return values are not being used hence returning 0
    function _claimRewards() internal virtual override returns (address, uint256) {
        ILiquidityGaugeV2 _curveGauge = curveGauge();
        if (block.chainid == 1) {
            CRV_MINTER.mint(address(_curveGauge));
        } else if (GAUGE_FACTORY.is_valid_gauge(address(_curveGauge))) {
            // On side chain gauge factory can mint CRV reward but only for valid gauge.
            GAUGE_FACTORY.mint(address(_curveGauge));
        }
        // solhint-disable-next-line no-empty-blocks
        try _curveGauge.claim_rewards() {} catch {
            // This call may fail in some scenarios
            // e.g. 3Crv gauge doesn't have such function
        }
        return (address(0), 0);
    }

    // @dev Convex strategy will have to override this to unstake from gauge and stake in Booster
    function _deposit() internal virtual {
        _depositAndStakeToCurve();
    }

    function _depositAndStakeToCurve() internal {
        CurveBaseStorage memory s = _getCurveBaseStorage();
        uint256[] memory _depositAmounts;
        uint256 _minMintAmount;
        uint256 _ethValue;
        {
            bool _isAmountZero;
            (_depositAmounts, _minMintAmount, _ethValue, _isAmountZero) = _getDepositData(s);
            if (_isAmountZero) return;
        }

        IDepositAndStake(s._depositAndStake).deposit_and_stake{value: _ethValue}(
            s._depositContract,
            address(s._curveLp),
            address(s._curveGauge),
            s._underlyingTokens.length,
            s._underlyingTokens,
            _depositAmounts,
            _minMintAmount,
            s._useUnderlying,
            s._useDynamicArray,
            s._curvePoolForDeposit
        );
    }

    function _getCurvePoolInfo(
        IMetaRegistry registry_,
        address curvePool_,
        address _weth
    )
        internal
        view
        returns (address[] memory _underlyingTokens, int128 _collateralIdx, bool _isMetaPool, bool _isLendingTokenPool)
    {
        /// Note: collateralToken() is defined in parent contract and must be initialized before reading it.
        address _collateralToken = address(collateralToken());
        // This is the actual number of underlying tokens in Curve pool
        uint256 _nCoins = registry_.get_n_underlying_coins(curvePool_);
        if (_nCoins > 4) revert MaxFourCoinsAreAllowed();
        // We will track underlyingTokens array. It has length equal to _nCoins.
        _underlyingTokens = new address[](_nCoins);
        // get_underlying_coins always returns array of 8 length
        address[8] memory _underlyingCoins = registry_.get_underlying_coins(curvePool_);
        uint256 _collateralPos = type(uint256).max;
        for (uint256 i; i < _nCoins; i++) {
            _underlyingTokens[i] = _underlyingCoins[i];
            if (_underlyingCoins[i] == _collateralToken || (_underlyingCoins[i] == ETH && _collateralToken == _weth)) {
                _collateralPos = i;
            }
        }
        if (_collateralPos > _nCoins) revert InvalidCollateral();

        _isMetaPool = registry_.is_meta(curvePool_);
        // we know that collateral is in _underlyingCoins but if it is not in get_coins then it is lendingTokenPool
        // A lendingToken pool is the one which hold lending(aToken, cToken) token as Curve collateral token.
        if (!_isMetaPool && _underlyingCoins[_collateralPos] != registry_.get_coins(curvePool_)[_collateralPos]) {
            _isLendingTokenPool = true;
        }
        _collateralIdx = int128(int256(_collateralPos));
    }

    function _getDepositData(CurveBaseStorage memory s) private returns (uint256[] memory, uint256, uint256, bool) {
        uint256[] memory _depositAmounts = new uint256[](8);
        uint256 _minMintAmount;
        uint256 _ethValue;
        bool _isAmountZero = true; // Assume deposit amount is zero

        // Iterate through all underlying tokens.
        // Check balance of underlyingToken to determine depositAmount
        // Get quote of underlying token to collateral to calculate minimum out
        uint256 _nCoins = s._underlyingTokens.length;
        for (uint256 i; i < _nCoins; i++) {
            address _underlyingToken = s._underlyingTokens[i];
            // ETH can be found at max once in underlyingTokens.
            if (_underlyingToken == ETH) {
                if (_ethValue != 0) revert OnlyOneEthAllowedInUnderlying();
                IWETH _weth = s._weth;
                _depositAmounts[i] = _weth.balanceOf(address(this));
                _weth.withdraw(_depositAmounts[i]);
                _ethValue = _depositAmounts[i];
                _minMintAmount += _getQuoteFromOracle(address(_weth), address(s._curveLp), _depositAmounts[i]);
            } else {
                _depositAmounts[i] = IERC20(_underlyingToken).balanceOf(address(this));
                _minMintAmount += _getQuoteFromOracle(_underlyingToken, address(s._curveLp), _depositAmounts[i]);
            }
            // If deposit amount for any underlyingToken is non zero then set the zero flag to false
            if (_depositAmounts[i] > 0) _isAmountZero = false;
        }
        _minMintAmount = (_minMintAmount * (MAX_BPS - s._slippage)) / MAX_BPS;
        return (_depositAmounts, _minMintAmount, _ethValue, _isAmountZero);
    }

    function _getQuoteFromOracle(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_
    ) private view returns (uint256) {
        if (tokenIn_ == tokenOut_) {
            return amountIn_;
        } else {
            return masterOracle().quote(tokenIn_, tokenOut_, amountIn_);
        }
    }

    function _getRewardTokens() internal view virtual returns (address[] memory _rewardTokens);

    function _quoteForWithdrawOneCoin(uint256 lpAmountIn_) private view returns (uint256 _amountOut) {
        CurveBaseStorage memory s = _getCurveBaseStorage();

        if (s._curvePoolZap != address(0)) {
            _amountOut = IWithdraw(s._curvePoolZap).calc_withdraw_one_coin(s._curvePool, lpAmountIn_, s._collateralIdx);
        } else {
            _amountOut = IWithdraw(s._curvePool).calc_withdraw_one_coin(lpAmountIn_, s._collateralIdx);
        }
    }

    function _quoteLpToCollateral(uint256 lpAmountIn_) private view returns (uint256 _amountOut) {
        if (lpAmountIn_ == 0) {
            return 0;
        }
        CurveBaseStorage memory s = _getCurveBaseStorage();

        if (s._curvePoolZap != address(0)) {
            _amountOut = IWithdraw(s._curvePoolZap).calc_withdraw_one_coin(s._curvePool, lpAmountIn_, s._collateralIdx);
        } else {
            _amountOut = IWithdraw(s._curvePool).calc_withdraw_one_coin(lpAmountIn_, s._collateralIdx);
        }
    }

    function _quoteWithSlippageCheck(uint256 lpAmountIn_) private view returns (uint256 _amountOut) {
        uint256 _oracleAmount = _getQuoteFromOracle(address(curveLp()), address(collateralToken()), lpAmountIn_);
        _amountOut = _quoteLpToCollateral(lpAmountIn_);
        if (_amountOut < (_oracleAmount * (MAX_BPS - slippage())) / MAX_BPS) revert SlippageTooHigh();
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = pool();
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _lpHere = lpBalanceHere();
        uint256 _totalLp = _lpHere + lpBalanceStaked();
        uint256 _collateralInCurve = _quoteWithSlippageCheck(_totalLp);
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _collateralHere + _collateralInCurve;

        if (_totalCollateral > _totalDebt) {
            _profit = _totalCollateral - _totalDebt;
        } else {
            _loss = _totalDebt - _totalCollateral;
        }

        uint256 _profitAndExcessDebt = _profit + _excessDebt;
        if (_profitAndExcessDebt > _collateralHere) {
            uint256 _totalAmountToWithdraw = _profitAndExcessDebt - _collateralHere;
            uint256 _lpToBurn = Math.min((_totalAmountToWithdraw * _totalLp) / _collateralInCurve, _totalLp);
            if (_lpToBurn > 0) {
                _withdrawHere(_lpHere, _lpToBurn);
                _collateralHere = _collateralToken.balanceOf(address(this));
            }
        }

        // Make sure _collateralHere >= _payback + profit. set actual payback first and then profit
        _payback = Math.min(_collateralHere, _excessDebt);
        _profit = _collateralHere > _payback ? Math.min((_collateralHere - _payback), _profit) : 0;

        _pool.reportEarning(_profit, _loss, _payback);
        _deposit();
    }

    function _unstakeLp(uint256 amount_) internal virtual {
        if (amount_ > 0) {
            curveGauge().withdraw(amount_);
        }
    }

    /// @dev It is okay to set 0 as _minOut as there is another check in place in calling function.
    function _withdrawAllCoinsFromCurve(uint256 nCoins_, uint256 lpToBurn_) private {
        CurveBaseStorage memory s = _getCurveBaseStorage();
        address _curvePool = s._curvePool;
        address _curvePoolZap = s._curvePoolZap;
        if (s._useDynamicArray) {
            IWithdraw(_curvePool).remove_liquidity(lpToBurn_, new uint256[](nCoins_));
        } else if (nCoins_ == 2) {
            uint256[2] memory _minOut;
            if (_curvePoolZap != address(0)) {
                IWithdraw(_curvePoolZap).remove_liquidity(lpToBurn_, _minOut);
            } else {
                IWithdraw(_curvePool).remove_liquidity(lpToBurn_, _minOut);
            }
        } else if (nCoins_ == 3) {
            uint256[3] memory _minOut;

            if (_curvePoolZap != address(0)) {
                IWithdraw(_curvePoolZap).remove_liquidity(_curvePool, lpToBurn_, _minOut);
            } else {
                IWithdraw(_curvePool).remove_liquidity(lpToBurn_, _minOut);
            }
        } else if (nCoins_ == 4) {
            uint256[4] memory _minOut;
            if (_curvePoolZap != address(0)) {
                IWithdraw(_curvePoolZap).remove_liquidity(_curvePool, lpToBurn_, _minOut);
            } else {
                IWithdraw(_curvePool).remove_liquidity(lpToBurn_, _minOut);
            }
        }
    }

    function _withdrawHere(uint256 coinAmountOut_) internal override {
        uint256 _lpHere = lpBalanceHere();
        uint256 _totalLp = _lpHere + lpBalanceStaked();
        uint256 _totalCollateral = _quoteLpToCollateral(_totalLp);
        uint256 _lpToBurn = Math.min((coinAmountOut_ * _totalLp) / _totalCollateral, _totalLp);
        if (_lpToBurn == 0) return;

        _withdrawHere(_lpHere, _lpToBurn);
    }

    function _withdrawHere(uint256 lpHere_, uint256 lpToBurn_) internal {
        if (lpToBurn_ > lpHere_) {
            _unstakeLp(lpToBurn_ - lpHere_);
        }

        address _collateralToken = address(collateralToken());
        CurveBaseStorage memory s = _getCurveBaseStorage();
        // We can check amountOut_ against collateral received but it will serve as extra security measure
        uint256 _oracleQuote = _getQuoteFromOracle(address(s._curveLp), _collateralToken, lpToBurn_);
        uint256 _minAmountOut = (_oracleQuote * (MAX_BPS - s._slippage)) / MAX_BPS;

        uint256 _collateralOut = _withdrawOneCoinFromCurve(s, lpToBurn_);

        if (_collateralOut < _minAmountOut) revert SlippageTooHigh();
    }

    function _withdrawOneCoinFromCurve(CurveBaseStorage memory s, uint256 lpToBurn_) internal returns (uint256) {
        // Withdraw is protected by collateral balance check at the end, so it if fine to use 1 as min out.
        uint256 _minOut = 1;
        int128 _i = s._collateralIdx;
        if (s._curvePoolZap != address(0)) {
            return IWithdraw(s._curvePoolZap).remove_liquidity_one_coin(s._curvePool, lpToBurn_, _i, _minOut);
        } else if (s._useUnderlying) {
            return IWithdraw(s._curvePool).remove_liquidity_one_coin(lpToBurn_, _i, _minOut, true);
        } else {
            return IWithdraw(s._curvePool).remove_liquidity_one_coin(lpToBurn_, _i, _minOut);
        }
    }

    /************************************************************************************************
     *                          Governor/admin/keeper function                                      *
     ***********************************************************************************************/

    /**
     * @notice Rewards token in gauge can be updated any time. This method refresh list.
     * It is recommended to claimAndSwapRewards before calling this function.
     */
    function refetchRewardTokens() external onlyGovernor {
        // 1. Claim rewards before updating rewardTokens
        _claimAndSwapRewards();
        // 2. Update rewardTokens array
        _getCurveBaseStorage()._rewardTokens = _getRewardTokens();
        // 3. Approve tokens. If needed, forceApprove will set approval to zero before setting new value.
        _approveToken(MAX_UINT_VALUE);
    }

    function updateSlippage(uint256 newSlippage_) external onlyGovernor {
        if (newSlippage_ >= MAX_BPS) revert InvalidSlippage();

        CurveBaseStorage storage $ = _getCurveBaseStorage();
        emit SlippageUpdated($._slippage, newSlippage_);
        $._slippage = newSlippage_;
    }

    function updateMasterOracle(IMasterOracle newMasterOracle_) external onlyGovernor {
        if (address(newMasterOracle_) == address(0)) revert AddressIsNull();

        CurveBaseStorage storage $ = _getCurveBaseStorage();
        emit MasterOracleUpdated($._masterOracle, newMasterOracle_);
        $._masterOracle = newMasterOracle_;
    }

    /// @notice onlyKeeper:This function will withdraw all underlying tokens from Curve as oppose to regular
    /// collateral withdrawal. Caller should call this via callStatic to get values for minAmountsOut.
    /// Note: In order to get collaterals, keeper will have swap underlying tokens to collateral.
    function withdrawAllCoins(uint256 minAmountOut_) external onlyKeeper returns (uint256 _amountOut) {
        uint256 _lpHere = lpBalanceHere();
        uint256 _lpStaked = lpBalanceStaked();
        uint256 _totalLp = _lpHere + lpBalanceStaked();

        if (_lpStaked > 0) {
            _unstakeLp(_lpStaked);
        }

        address _collateralToken = address(collateralToken());
        uint256 _collateralBefore = IERC20(_collateralToken).balanceOf(address(this));
        CurveBaseStorage memory s = _getCurveBaseStorage();

        address[] memory _underlyingTokens = s._underlyingTokens;
        uint256 _nCoins = _underlyingTokens.length;

        _withdrawAllCoinsFromCurve(_nCoins, _totalLp);

        for (uint256 i; i < _nCoins; i++) {
            address _underlyingToken = _underlyingTokens[i];
            if (_underlyingToken == _collateralToken) {
                continue;
            }
            uint256 _underlyingBalance = IERC20(_underlyingToken).balanceOf(address(this));
            if (_underlyingBalance > 0) {
                _swapExactInput(_underlyingToken, _collateralToken, _underlyingBalance);
            }
        }
        _amountOut = IERC20(_collateralToken).balanceOf(address(this)) - _collateralBefore;
        if (_amountOut < minAmountOut_) revert SlippageTooHigh();
    }
}
