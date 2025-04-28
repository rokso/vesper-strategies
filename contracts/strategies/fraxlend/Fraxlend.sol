// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../Strategy.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {IFraxlendPair} from "../../interfaces/fraxlend/IFraxlendPair.sol";

/// @title This strategy will deposit FRAX as collateral token in Fraxlend and earn interest.
abstract contract Fraxlend is Strategy {
    using SafeERC20 for IERC20;

    error CollateralMismatch();

    function __Fraxlend_init(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) internal initializer {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);
        if (IFraxlendPair(receiptToken_).asset() != address(collateralToken())) revert CollateralMismatch();
    }

    function fraxlendPair() public view returns (IFraxlendPair) {
        return IFraxlendPair(receiptToken());
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return token_ == receiptToken();
    }

    function tvl() external view override returns (uint256) {
        return _balanceOfUnderlying() + collateralToken().balanceOf(address(this));
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal override {
        IERC20 _collateralToken = collateralToken();
        _collateralToken.forceApprove(pool(), amount_);
        _collateralToken.forceApprove(address(fraxlendPair()), amount_);
    }

    function _balanceOfUnderlying() internal view virtual returns (uint256);

    /**
     * @notice Deposit collateral in Fraxlend.
     */
    function _deposit(uint256 amount_) internal {
        if (amount_ > 0) {
            fraxlendPair().deposit(amount_, address(this));
        }
    }

    /**
     * @dev Generate report for pools accounting and also send profit and any payback to pool.
     */
    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _collateralHere + _balanceOfUnderlying();
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
        // After reportEarning strategy may get more collateral from pool. Deposit those in protocol.
        _deposit(_collateralToken.balanceOf(address(this)));
    }
}
