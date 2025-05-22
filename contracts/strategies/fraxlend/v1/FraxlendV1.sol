// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFraxlendPair} from "../../../interfaces/fraxlend/IFraxlendPair.sol";
import {Fraxlend} from "../Fraxlend.sol";

/// @title This strategy will deposit FRAX as collateral token in Fraxlend and earn interest.
contract FraxlendV1 is Fraxlend {
    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) external initializer {
        __Fraxlend_init(pool_, swapper_, receiptToken_, name_);
    }

    function _balanceOfUnderlying() internal view override returns (uint256) {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        return _fraxlendPair.toAssetAmount(_fraxlendPair.balanceOf(address(this)), false);
    }

    function _withdrawHere(uint256 amount_) internal override {
        IFraxlendPair _fraxlendPair = fraxlendPair();
        // Check protocol has enough assets to entertain this withdraw amount_
        uint256 _withdrawAmount = Math.min(
            amount_,
            (_fraxlendPair.totalAsset().amount - _fraxlendPair.totalBorrow().amount)
        );

        // Check we have enough LPs for this withdraw
        uint256 _sharesToWithdraw = Math.min(
            _fraxlendPair.toAssetShares(_withdrawAmount, false),
            _fraxlendPair.balanceOf(address(this))
        );

        if (_sharesToWithdraw > 0) {
            _fraxlendPair.redeem(_sharesToWithdraw, address(this), address(this));
        }
    }
}
