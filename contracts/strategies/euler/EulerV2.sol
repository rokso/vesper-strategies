// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../Strategy.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {IEulerV2} from "../../interfaces/euler/IEulerV2.sol";

/**
 * @title Euler V2 strategy.
 * @notice This strategy will supply collateral in Euler Vault. Vault is ERC4626 implementation.
 */
contract EulerV2 is Strategy {
    using SafeERC20 for IERC20;

    error InvalidVault();

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) external initializer {
        if (receiptToken_ == address(0)) revert AddressIsNull();
        __Strategy_init(pool_, swapper_, receiptToken_, name_);
        if (IEulerV2(receiptToken_).asset() != address(IVesperPool(pool_).token())) revert InvalidVault();
    }

    function euler() public view returns (IEulerV2) {
        return IEulerV2(receiptToken());
    }

    function isReservedToken(address token_) public view virtual override returns (bool) {
        return token_ == address(euler());
    }

    function tvl() external view override returns (uint256) {
        return _getCollateralInProtocol() + collateralToken().balanceOf(address(this));
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal virtual override {
        super._approveToken(amount_);
        collateralToken().forceApprove(address(euler()), amount_);
    }

    /**
     * @dev Deposit collateral in Euler Vault.
     */
    function _deposit(uint256 amount_) internal virtual {
        IEulerV2 _euler = euler();
        if (_euler.convertToShares(amount_) > 0) {
            _euler.deposit(amount_, address(this));
        }
    }

    /// Get total collateral deposited in protocol
    function _getCollateralInProtocol() internal view returns (uint256) {
        IEulerV2 _euler = euler();
        return _euler.convertToAssets(_euler.balanceOf(address(this)));
    }

    /**
     * @dev Generate report for pools accounting and also send profit and any payback to pool.
     */
    function _rebalance() internal virtual override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

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
        // After reportEarning strategy may get more collateral from pool. Deposit those in Euler Vault.
        _deposit(_collateralToken.balanceOf(address(this)));
    }

    /// @dev Withdraw collateral here.
    function _withdrawHere(uint256 amount_) internal override {
        IEulerV2 _euler = euler();
        // Get minimum of amount_ and _available collateral
        uint256 _withdrawAmount = Math.min(amount_, _euler.maxWithdraw(address(this)));
        _euler.withdraw(_withdrawAmount, address(this), address(this));
    }
}
