// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../Strategy.sol";
import {IVesperPool} from "../../interfaces/vesper/IVesperPool.sol";
import {IYToken} from "../../interfaces/yearn/IYToken.sol";

/// @title This strategy will deposit collateral token in a Yearn vault and earn interest.
contract Yearn is Strategy {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:vesper.storage.Strategy.Yearn
    struct YearnStorage {
        uint256 _yTokenDecimals;
    }

    bytes32 private constant YearnStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.Yearn")) - 1)) & ~bytes32(uint256(0xff));

    function _getYearnStorage() internal pure returns (YearnStorage storage $) {
        bytes32 _location = YearnStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) external initializer {
        __Strategy_init(pool_, swapper_, receiptToken_, name_);

        _getYearnStorage()._yTokenDecimals = 10 ** IYToken(receiptToken_).decimals();
    }

    function tvl() external view override returns (uint256) {
        return _getCollateralFromYearn() + collateralToken().balanceOf(address(this));
    }

    function yToken() public view returns (IYToken) {
        return IYToken(receiptToken());
    }

    function yTokenDecimals() internal view returns (uint256) {
        return _getYearnStorage()._yTokenDecimals;
    }

    /// @notice Approve all required tokens
    function _approveToken(uint256 amount_) internal override {
        super._approveToken(amount_);
        collateralToken().forceApprove(address(yToken()), amount_);
    }

    function _convertToShares(uint256 collateralAmount_) internal view returns (uint256) {
        return (collateralAmount_ * yTokenDecimals()) / yToken().pricePerShare();
    }

    function _getCollateralFromYearn() internal view returns (uint256) {
        IYToken _yToken = yToken();
        return (_yToken.balanceOf(address(this)) * _yToken.pricePerShare()) / yTokenDecimals();
    }

    function _rebalance() internal override returns (uint256 _profit, uint256 _loss, uint256 _payback) {
        IVesperPool _pool = pool();
        uint256 _excessDebt = _pool.excessDebt(address(this));
        uint256 _totalDebt = _pool.totalDebtOf(address(this));

        IERC20 _collateralToken = collateralToken();
        uint256 _collateralHere = _collateralToken.balanceOf(address(this));
        uint256 _totalCollateral = _getCollateralFromYearn() + _collateralHere;

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
            yToken().deposit(_collateralHere);
        }
    }

    function _withdrawHere(uint256 amount_) internal override {
        IYToken _yToken = yToken();
        uint256 _toWithdraw = Math.min(_yToken.balanceOf(address(this)), _convertToShares(amount_));
        if (_toWithdraw > 0) {
            _yToken.withdraw(_toWithdraw);
        }
    }
}
