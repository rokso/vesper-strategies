// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFraxlendPairV3} from "../../interfaces/fraxlend/IFraxlendPairV3.sol";
import {Fraxlend} from "./Fraxlend.sol";

/// @title This strategy will deposit FRAX as collateral token in Fraxlend and earn interest.
contract FraxlendV3 is Fraxlend {
    function initialize(
        address pool_,
        address swapper_,
        address receiptToken_,
        string memory name_
    ) external initializer {
        __Fraxlend_init(pool_, swapper_, receiptToken_, name_);
    }

    function _balanceOfUnderlying() internal view override returns (uint256) {
        IFraxlendPairV3 _fraxlendPair = _fraxlendPairV3();
        return _fraxlendPair.convertToAssets(_fraxlendPair.balanceOf(address(this)));
    }

    function _fraxlendPairV3() private view returns (IFraxlendPairV3) {
        return IFraxlendPairV3(receiptToken());
    }

    function _withdrawHere(uint256 amount_) internal override {
        IFraxlendPairV3 _fraxlendPair = _fraxlendPairV3();
        // Check protocol has enough assets to entertain this withdraw amount_
        uint256 _withdrawAmount = Math.min(amount_, _fraxlendPair.maxWithdraw(address(this)));
        _fraxlendPair.withdraw(_withdrawAmount, address(this), address(this));
    }
}
