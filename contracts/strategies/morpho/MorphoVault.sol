// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../Strategy.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {IMetaMorpho} from "../../interfaces/morpho/IMetaMorpho.sol";

/**
 * @title Morpho Vault (MetaMorpho) strategy.
 * @notice This strategy will supply collateral in Morpho Vault. Vault is ERC4626 implementation.
 * It may earn some rewards. Anyone can claim rewards on behalf of this address on Universal Reward Distributor(URD).
 */
contract MorphoVault is Strategy {
    using SafeERC20 for IERC20;

    error InvalidVault();

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) external initializer {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);
        if (IMetaMorpho(receiptToken_).asset() != address(IVesperPool(pool_).token())) revert InvalidVault();
    }

    /// @dev Morpho vault token is not reserved as we will sweep it out for swap.
    function isReservedToken(address token_) public view override returns (bool) {
        return token_ == address(metaMorpho());
    }

    function metaMorpho() public view returns (IMetaMorpho) {
        return IMetaMorpho(receiptToken());
    }

    function tvl() external view override returns (uint256) {
        return _getCollateralInProtocol() + collateralToken().balanceOf(address(this));
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        collateralToken().forceApprove(address(metaMorpho()), amount_);
    }

    /**
     * @dev Deposit collateral in Morpho Vault.
     */
    function _deposit(uint256 amount_) internal {
        if (amount_ > 0) {
            metaMorpho().deposit(amount_, address(this));
        }
    }

    /// Get total collateral deposited in protocol
    function _getCollateralInProtocol() internal view returns (uint256) {
        IMetaMorpho _metaMorpho = metaMorpho();
        return _metaMorpho.convertToAssets(_metaMorpho.balanceOf(address(this)));
    }

    /**
     * @dev Generate report for pools accounting and also send profit and any payback to pool.
     */
    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _totalDebt = _pool.totalDebtOf(address(this));
        uint256 _excessDebt = _pool.excessDebt(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _collateralHere + _getCollateralInProtocol();
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
        // After reportEarning strategy may get more collateral from pool. Deposit those in Morpho Vault.
        _deposit(_collateralToken.balanceOf(address(this)));
    }

    /// @dev Withdraw collateral here.
    function _withdrawHere(uint256 _amount) internal override {
        IMetaMorpho _metaMorpho = metaMorpho();
        // Get minimum of _amount and _available collateral
        uint256 _withdrawAmount = Math.min(_amount, _metaMorpho.maxWithdraw(address(this)));
        _metaMorpho.withdraw(_withdrawAmount, address(this), address(this));
    }
}
