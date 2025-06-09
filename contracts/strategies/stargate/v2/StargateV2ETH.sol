// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strategy} from "../../Strategy.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";
import {IStargatePoolV2 as IStargatePool} from "../../../interfaces/stargate/v2/IStargatePoolV2.sol";
import {IStargateStaking} from "../../../interfaces/stargate/v2/IStargateStaking.sol";
import {StargateV2} from "./StargateV2.sol";

/// @title This Strategy will deposit ETH in a Stargate V2 Pool
/// Stake LP Token and accrue swap rewards
contract StargateV2ETH is StargateV2 {
    using SafeERC20 for IWETH;

    error InvalidStargateDecimals();

    /// @custom:storage-location erc7201:vesper.storage.Strategy.StargateV2.ETH
    struct StargateV2ETHStorage {
        IWETH _weth;
        uint256 _convertRate; // The rate between local decimals and shared decimals.
    }

    bytes32 private constant StargateV2ETHStorageLocation =
        keccak256(abi.encode(uint256(keccak256("vesper.storage.Strategy.StargateV2.ETH")) - 1)) &
            ~bytes32(uint256(0xff));

    function _getStargateV2ETHStorage() internal pure returns (StargateV2ETHStorage storage $) {
        bytes32 _location = StargateV2ETHStorageLocation;
        assembly {
            $.slot := _location
        }
    }

    function StargateV2ETH_initialize(
        address pool_,
        address swapper_,
        IStargatePool stargatePool_,
        IStargateStaking stargateStaking_,
        IWETH weth_,
        string memory name_
    ) external initializer {
        super.initialize(pool_, swapper_, stargatePool_, stargateStaking_, name_);

        if (address(weth_) == address(0)) revert AddressIsNull();

        StargateV2ETHStorage storage $ = _getStargateV2ETHStorage();
        $._weth = weth_;

        uint8 _sharedDecimals = stargatePool().sharedDecimals();
        uint8 _localDecimals = IERC20Metadata(address(stargateLp())).decimals();
        if (_localDecimals <= _sharedDecimals) revert InvalidStargateDecimals();

        $._convertRate = 10 ** (_localDecimals - _sharedDecimals);
    }

    receive() external payable {
        /// @dev Stargate will send ETH when we withdraw from Stargate ETH pool.
        /// So convert ETH to WETH if ETH sender is not WETH contract.
        IWETH _weth = weth();
        if (msg.sender != address(_weth)) {
            _weth.deposit{value: address(this).balance}();
        }
    }

    function convertRate() public view returns (uint256) {
        return _getStargateV2ETHStorage()._convertRate;
    }

    function weth() public view returns (IWETH) {
        return _getStargateV2ETHStorage()._weth;
    }

    /**
     * @dev Stargate has concept of sharedDecimals and localDecimals.
     * The amount we supply is in localDecimals and stargate convert it into sharedDecimals and back.
     * By doing this stargate removes dust from input amount.
     * In case of native pool, stargate expects users to provide proper input and has an assert to enforce this.
     * @param amountLD_ amount in local decimals
     */
    function _deDustAmount(uint256 amountLD_) internal view returns (uint256) {
        uint256 _convertRate = convertRate();
        // uint256 _amountSD = amountLD_ / convertRate;
        // uint256 _amountLD = _amountSD * convertRate;
        return (amountLD_ / _convertRate) * _convertRate;
    }

    /**
     * @dev Stargate ETH strategy supports ETH as collateral and Vesper deals
     * in WETH. Hence withdraw ETH from WETH before depositing in Stargate pool
     */
    function _deposit(uint256 collateralAmount_) internal override {
        collateralAmount_ = _deDustAmount(collateralAmount_);
        if (collateralAmount_ > 0) {
            weth().withdraw(collateralAmount_);
            stargatePool().deposit{value: collateralAmount_}(address(this), collateralAmount_);
        }
    }
}
