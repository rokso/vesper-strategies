// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../Strategy.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {ICellar} from "../../interfaces/sommelier/ISommelier.sol";
import {SommelierBase} from "./SommelierBase.sol";

/// @dev This strategy will deposit collateral token in Sommelier and earn yield.
contract Sommelier is Strategy, SommelierBase {
    using SafeERC20 for IERC20;

    error InvalidReceiptToken();

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) external initializer {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);
        __Sommelier_init(receiptToken_);
        if (ICellar(receiptToken_).asset() != address(IVesperPool(pool_).token())) revert InvalidReceiptToken();
    }

    function isReservedToken(address token_) public view override returns (bool) {
        return token_ == receiptToken();
    }

    function tvl() public view override returns (uint256) {
        return _getAssetsInSommelier() + collateralToken().balanceOf(address(this));
    }

    /// @notice Large approval of token
    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        collateralToken().forceApprove(address(cellar()), amount_);
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = IVesperPool(pool());
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _getAssetsInSommelier() + _collateralHere;
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
            cellar().deposit(_collateralHere, address(this));
        }
    }

    /// @dev Withdraw collateral here
    function _withdrawHere(uint256 requireAmount_) internal override {
        _withdrawFromSommelier(requireAmount_);
    }
}
