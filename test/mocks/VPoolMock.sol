// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract VPoolMock {
    using Math for uint256;

    IERC20 public immutable token;
    uint256 public target; // VPool.strategy[strategy].debtRatio * VPool.totalValue / MAX_BPS
    uint256 public latest; // VPool.strategy[strategy].totalDebt

    constructor(address token_) {
        token = IERC20(token_);
    }

    function updateDebtOfStrategy(uint256 target_, uint256 latest_) external {
        target = target_;
        latest = latest_;
    }

    function excessDebt(address) public view returns (uint256 _excessDebt) {
        (, _excessDebt) = latest.trySub(target);
    }

    function creditLimit(address) public view returns (uint256 _creditLimit) {
        (, _creditLimit) = target.trySub(latest);
    }

    function totalDebtOf(address) public view returns (uint256 _totalDebt) {
        _totalDebt = latest;
    }

    function reportEarning(uint256 profit_, uint256 /*loss_*/, uint256 payback_) external {
        address _strategy = msg.sender;

        uint256 _actualPayback = Math.min(excessDebt(_strategy), payback_);
        uint256 _creditLine = creditLimit(_strategy);
        uint256 _totalPayback = profit_ + _actualPayback;

        if (_totalPayback < _creditLine) {
            token.transfer(_strategy, _creditLine - _totalPayback);
        } else if (_totalPayback > _creditLine) {
            token.transferFrom(_strategy, address(this), _totalPayback - _creditLine);
        }
    }
}
