// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISafeExecutor} from "./interfaces/ISafeExecutor.sol";

/// @title SafeExecutor
/// @notice A contract that executes calls to other contracts
/// NOTE: this contract should not hold any funds, it's only used to execute calls to other contracts
contract SafeExecutor is ISafeExecutor {
    address public immutable OWNER;

    constructor() {
        OWNER = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert Unauthorized();
        }
        _;
    }

    /// @inheritdoc ISafeExecutor
    function execute(address target, bytes calldata data) external onlyOwner {
        if (target.code.length == 0) {
            revert InvalidTarget();
        }

        // solhint-disable avoid-low-level-calls
        // slither-disable-next-line low-level-calls
        (bool success,) = target.call(data);

        if (!success) {
            revert CallFailed();
        }
    }
}
