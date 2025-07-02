// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IStrategy} from "../interfaces/vesper/IStrategy.sol";
import {IVesperPool} from "../interfaces/vesper/IVesperPool.sol";
import {ISwapper} from "../interfaces/swapper/ISwapper.sol";

// solhint-disable no-empty-blocks
abstract contract Strategy is Initializable, UUPSUpgradeable, IStrategy {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    error AddressIsNull();
    error CanNotSweepToken();
    error FeeCollectorNotSet();
    error InvalidStrategy();
    error NotEnoughAmountOut();
    error NotEnoughProfit(uint256);
    error TooMuchLoss(uint256);
    error Unauthorized();

    event UpdatedFeeCollector(address oldFeeCollector, address newFeeCollector);
    event UpdatedSwapper(ISwapper oldSwapper, ISwapper newSwapper);

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant MAX_UINT_VALUE = type(uint256).max;
    /// @custom:storage-location erc7201:vesper.storage.Strategy
    struct StrategyStorage {
        IERC20 _collateralToken;
        address _pool;
        address _receiptToken;
        address _feeCollector;
        ISwapper _swapper;
        EnumerableSet.AddressSet _keepers;
        string _name;
    }

    bytes32 private constant StrategyStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy")) - 1)) & ~bytes32(uint256(0xff));

    function _getStrategyStorage() private pure returns (StrategyStorage storage $) {
        bytes32 _location = StrategyStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __Strategy_init(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        if (pool_ == address(0) || swapper_ == address(0) || receiptToken_ == address(0)) revert AddressIsNull();
        StrategyStorage storage $ = _getStrategyStorage();
        $._pool = pool_;
        $._collateralToken = IVesperPool(pool_).token();
        $._receiptToken = receiptToken_;
        // Set pool governor as default feeCollector
        $._feeCollector = IVesperPool(pool_).governor();
        $._swapper = ISwapper(swapper_);
        $._name = name_;
        $._keepers.add(msg.sender);
    }

    modifier onlyGovernor() {
        if (msg.sender != governor()) revert Unauthorized();
        _;
    }

    modifier onlyKeeper() {
        if (!_getStrategyStorage()._keepers.contains(msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlyPool() {
        if (msg.sender != address(pool())) revert Unauthorized();
        _;
    }

    function collateralToken() public view virtual override returns (IERC20) {
        return _getStrategyStorage()._collateralToken;
    }

    function feeCollector() public view returns (address) {
        return _getStrategyStorage()._feeCollector;
    }

    function governor() public view returns (address) {
        return pool().governor();
    }

    function isActive() external view override returns (bool) {
        (bool _isActive, , , , , , , , ) = pool().strategy(address(this));
        return _isActive;
    }

    /// @notice Check whether given token is reserved or not. Reserved tokens are not allowed to sweep.
    function isReservedToken(address token_) public view virtual override returns (bool) {
        return token_ == receiptToken() || token_ == address(collateralToken());
    }

    /// @notice Return list of keepers
    function keepers() external view override returns (address[] memory) {
        return _getStrategyStorage()._keepers.values();
    }

    function NAME() external view returns (string memory) {
        return _getStrategyStorage()._name;
    }

    function pool() public view override returns (IVesperPool) {
        return IVesperPool(_getStrategyStorage()._pool);
    }

    function poolAccountant() external view returns (address) {
        return pool().poolAccountant();
    }

    function receiptToken() public view virtual override returns (address) {
        return _getStrategyStorage()._receiptToken;
    }

    function swapper() public view returns (ISwapper) {
        return _getStrategyStorage()._swapper;
    }

    /// @notice Returns total collateral locked in the strategy
    function tvl() external view virtual returns (uint256);

    function VERSION() external pure virtual override returns (string memory) {
        return "6.0.1";
    }

    /**
     * @notice onlyGovernor: Add given address in keepers list.
     * @param keeperAddress_ keeper address to add.
     */
    function addKeeper(address keeperAddress_) external onlyGovernor {
        _getStrategyStorage()._keepers.add(keeperAddress_);
    }

    /// @dev OnlyKeeper: Approve all required tokens
    function approveToken(uint256 approvalAmount_) external onlyKeeper {
        _approveToken(approvalAmount_);
    }

    /// @notice OnlyKeeper: Claim rewards from protocol.
    /// @dev Claim rewardToken and convert rewardToken into collateral token.
    function claimAndSwapRewards(uint256 minAmountOut_) external onlyKeeper returns (uint256 _amountOut) {
        IERC20 _collateralToken = collateralToken();
        uint256 _collateralBefore = _collateralToken.balanceOf(address(this));
        _claimAndSwapRewards();
        _amountOut = _collateralToken.balanceOf(address(this)) - _collateralBefore;
        if (_amountOut < minAmountOut_) revert NotEnoughAmountOut();
    }

    /**
     * @notice OnlyKeeper: Rebalance profit, loss and investment of this strategy.
     *  Calculate profit, loss and payback of this strategy and realize profit/loss and
     *  withdraw fund for payback, if any, and submit this report to pool.
     * @param minProfit_ Minimum profit expected from this call.
     * @param maxLoss_ Maximum accepted loss for this call.
     * @return _profit Realized profit in collateral.
     * @return _loss Realized loss, if any, in collateral.
     * @return _payback If strategy has any excess debt, we have to liquidate asset to payback excess debt.
     */
    function rebalance(
        uint256 minProfit_,
        uint256 maxLoss_
    ) external onlyKeeper returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        (_profit, _loss, _payback) = _rebalance();
        if (_profit < minProfit_) revert NotEnoughProfit(_profit);
        if (_loss > maxLoss_) revert TooMuchLoss(_loss);
    }

    /**
     * @notice onlyGovernor: Remove given address from keepers list.
     * @param keeperAddress_ keeper address to remove.
     */
    function removeKeeper(address keeperAddress_) external onlyGovernor {
        _getStrategyStorage()._keepers.remove(keeperAddress_);
    }

    /// @notice onlyKeeper: Swap given token into collateral token.
    function swapToCollateral(IERC20 tokenIn_, uint256 minAmountOut_) external onlyKeeper returns (uint256 _amountOut) {
        StrategyStorage storage $ = _getStrategyStorage();
        IERC20 _collateralToken = $._collateralToken;
        address _swapper = address($._swapper);

        if (address(tokenIn_) == address(_collateralToken) || isReservedToken(address(tokenIn_)))
            revert CanNotSweepToken();
        uint256 _collateralBefore = _collateralToken.balanceOf(address(this));
        uint256 _amountIn = tokenIn_.balanceOf(address(this));
        if (_amountIn > 0) {
            if (_amountIn > tokenIn_.allowance(address(this), _swapper)) {
                // if needed, forceApprove will set approval to zero before setting new value.
                tokenIn_.forceApprove(_swapper, MAX_UINT_VALUE);
            }
            _swapExactInput(address(tokenIn_), address(_collateralToken), _amountIn);
        }
        _amountOut = _collateralToken.balanceOf(address(this)) - _collateralBefore;
        if (_amountOut < minAmountOut_) revert NotEnoughAmountOut();
    }

    /**
     * @notice onlyKeeper: sweep given token to feeCollector of strategy
     * @param fromToken_ token address to sweep
     */
    function sweep(address fromToken_) external override onlyKeeper {
        address _feeCollector = feeCollector();
        if (_feeCollector == address(0)) revert FeeCollectorNotSet();
        if (fromToken_ == address(collateralToken()) || isReservedToken(fromToken_)) revert CanNotSweepToken();
        if (fromToken_ == ETH) {
            Address.sendValue(payable(_feeCollector), address(this).balance);
        } else {
            uint256 _amount = IERC20(fromToken_).balanceOf(address(this));
            IERC20(fromToken_).safeTransfer(_feeCollector, _amount);
        }
    }

    /**
     * @notice onlyGovernor: Update fee collector
     * @param feeCollector_ fee collector address
     */
    function updateFeeCollector(address feeCollector_) external onlyGovernor {
        if (feeCollector_ == address(0)) revert AddressIsNull();
        StrategyStorage storage $ = _getStrategyStorage();
        emit UpdatedFeeCollector($._feeCollector, feeCollector_);
        $._feeCollector = feeCollector_;
    }

    /**
     * @notice onlyGovernor: Update swapper
     * @param swapper_ swapper address
     */
    function updateSwapper(ISwapper swapper_) external onlyGovernor {
        if (address(swapper_) == address(0)) revert AddressIsNull();
        StrategyStorage storage $ = _getStrategyStorage();
        emit UpdatedSwapper($._swapper, swapper_);
        $._swapper = swapper_;
    }

    /**
     * @notice onlyPool: Withdraw collateral token from end protocol.
     * @param amount_ Amount of collateral token
     */
    function withdraw(uint256 amount_) external override onlyPool {
        IVesperPool _pool = pool();
        // In most cases _token and collateralToken() are same but in case of
        // vastETH pool they can be different, stETH and wstETH respectively.
        IERC20 _token = _pool.token();
        uint256 _tokensHere = _token.balanceOf(address(this));
        if (_tokensHere >= amount_) {
            _token.safeTransfer(address(_pool), amount_);
        } else {
            _withdrawHere(amount_ - _tokensHere);
            // Do not assume _withdrawHere() will withdraw exact amount. Check balance again and transfer to pool
            _tokensHere = _token.balanceOf(address(this));
            _token.safeTransfer(address(_pool), Math.min(amount_, _tokensHere));
        }
    }

    function _approveToken(uint256 amount_) internal virtual {
        StrategyStorage storage $ = _getStrategyStorage();
        $._collateralToken.forceApprove($._pool, amount_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}

    function _claimAndSwapRewards() internal virtual {
        (address _rewardToken, uint256 _rewardsAmount) = _claimRewards();
        if (_rewardsAmount > 0) {
            _trySwapExactInput(_rewardToken, address(collateralToken()), _rewardsAmount);
        }
    }

    function _claimRewards() internal virtual returns (address, uint256) {}

    function _rebalance() internal virtual returns (uint256 _profit, uint256 _loss, uint256 _payback);

    function _swapExactInput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_
    ) internal returns (uint256 _amountOut) {
        _amountOut = swapper().swapExactInput(tokenIn_, tokenOut_, amountIn_, 1, address(this));
    }

    function _trySwapExactInput(address tokenIn_, address tokenOut_, uint256 amountIn_) internal returns (uint256) {
        try swapper().swapExactInput(tokenIn_, tokenOut_, amountIn_, 1, address(this)) returns (uint256 _amountOut) {
            return _amountOut;
        } catch {
            return 0;
        }
    }

    function _withdrawHere(uint256 amount_) internal virtual;
}
