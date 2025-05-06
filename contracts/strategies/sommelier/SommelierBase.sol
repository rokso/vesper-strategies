// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICellar} from "../../interfaces/sommelier/ISommelier.sol";

/// @dev This strategy will deposit collateral token in Sommelier and earn yield.
abstract contract SommelierBase {
    /// @custom:storage-location erc7201:vesper.storage.Strategy.SommelierBase
    struct SommelierBaseStorage {
        ICellar _cellar;
    }

    bytes32 private constant SommelierBaseStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.SommelierBase")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getSommelierBaseStorage() internal pure returns (SommelierBaseStorage storage $) {
        bytes32 _location = SommelierBaseStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function __Sommelier_init(address cellar_) internal {
        _getSommelierBaseStorage()._cellar = ICellar(cellar_);
    }

    function cellar() public view returns (ICellar) {
        return _getSommelierBaseStorage()._cellar;
    }

    /**
     * @notice Time when withdraw and transfer will be unlocked.
     */
    function unlockTime() public view returns (uint256) {
        ICellar _cellar = cellar();
        return _cellar.userShareLockStartTime(address(this)) + _cellar.shareLockPeriod();
    }

    function _depositInSommelier(uint256 amount_) internal returns (uint256 shares_) {
        ICellar _cellar = cellar();
        if (_cellar.previewDeposit(amount_) != 0) {
            shares_ = _cellar.deposit(amount_, address(this));
        }
    }

    function _getAssetsInSommelier() internal view returns (uint256) {
        ICellar _cellar = cellar();
        return _cellar.convertToAssets(_cellar.balanceOf(address(this)));
    }

    /**
     * @dev Withdraw from sommelier vault
     * @param requireAmount_ equivalent value of the assets withdrawn, denominated in the cellar's asset
     * @return shares_ amount of shares redeemed
     */
    function _withdrawFromSommelier(uint256 requireAmount_) internal returns (uint256 shares_) {
        if (block.timestamp >= unlockTime()) {
            ICellar _cellar = cellar();
            // withdraw asking more than available liquidity will fail. To do safe withdraw, check
            // requireAmount_ against available liquidity.
            uint256 _withdrawable = Math.min(
                requireAmount_,
                Math.min(_getAssetsInSommelier(), _cellar.totalAssetsWithdrawable())
            );
            if (_withdrawable > 0) {
                shares_ = _cellar.withdraw(_withdrawable, address(this), address(this));
            }
        }
    }
}
