// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISafeExecutor} from "./interfaces/ISafeExecutor.sol";

/// @title SafeExecutor
/// @notice A contract that executes calls to other contracts, and emits an event when the call is successful
/// NOTE: this contract should not hold any funds, it's only used to execute calls to other contracts
contract SafeExecutor is ISafeExecutor {
    /// @inheritdoc ISafeExecutor
    function execute(address target, bytes calldata data) external returns (bytes memory) {
        if (target.code.length == 0) {
            revert InvalidTarget();
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = target.call(data);

        if (!success) {
            revert CallFailed();
        } else {
            emit Executed(target, result);
        }

        return result;
    }
}
