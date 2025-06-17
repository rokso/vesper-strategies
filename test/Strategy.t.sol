// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strategy} from "contracts/strategies/Strategy.sol"; // Adjust the import path as needed
import {IVesperPool} from "contracts/interfaces/vesper/IVesperPool.sol";
import {SwapperMock} from "test/mocks/SwapperMock.sol";
import {MasterOracleMock} from "test/mocks/MasterOracleMock.sol";
import {VPoolMock} from "test/mocks/VPoolMock.sol";

abstract contract Strategy_Test is Test {
    uint256 internal constant MAX_BPS = 100_00;

    uint256 immutable MAX_DEPOSIT_SLIPPAGE_REL = 0;
    uint256 immutable MAX_WITHDRAW_SLIPPAGE_REL = 0;
    uint256 immutable MAX_DUST_LEFT_IN_PROTOCOL_AFTER_WITHDRAW_ABS = 0;

    Strategy public strategy;
    address public governor = makeAddr("governor");
    VPoolMock public pool;
    SwapperMock public swapperMock;
    MasterOracleMock public masterOracleMock;

    function _setUp() internal virtual;

    function setUp() public {
        masterOracleMock = new MasterOracleMock();
        swapperMock = new SwapperMock(masterOracleMock);

        _setUp();

        require(address(strategy) != address(0), "Strategy not instantiated");
        strategy.approveToken(type(uint256).max);

        _mockVesperPool();
        console.log("running fork from block", block.number);
    }

    /// @dev If fork is not active then create and select fork.
    /// If tests are invoked as "forge test --fork-url node_url" then there is
    /// an active fork already and we want to respect that.
    function createSelectFork(string memory urlOrAlias) public returns (uint256 forkId) {
        try vm.activeFork() returns (uint256 _forkId) {
            return _forkId;
        } catch {
            return vm.createSelectFork(urlOrAlias);
        }
    }

    function _mockVesperPool() private {
        address _poolAddress = address(strategy.pool());

        pool = VPoolMock(_poolAddress);

        deal(address(token()), address(pool), 0);

        vm.etch(_poolAddress, address(new VPoolMock(address(token()))).code);

        vm.mockCall(_poolAddress, abi.encodeWithSelector(IVesperPool.governor.selector), abi.encode(governor));
    }

    function token() internal view returns (IERC20) {
        return pool.token();
    }

    function parseAmount(uint256 amount) internal view returns (uint256) {
        return amount * 10 ** IERC20Metadata(address(token())).decimals();
    }

    function _getWrappedAmount(uint256 amount) internal view virtual returns (uint256) {
        return amount;
    }

    function _waitForUnlockTime() internal virtual {}

    function _rebalance() internal virtual {
        _waitForUnlockTime();
        strategy.rebalance(0, type(uint256).max);
    }

    function _makeProfit(uint256 profit) internal virtual;

    function _makeLoss(uint256 loss) internal virtual;

    function _poolInitialAmount() internal view virtual returns (uint256) {
        return parseAmount(1_000);
    }
}
