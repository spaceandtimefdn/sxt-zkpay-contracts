// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ISafeExecutor
/// @notice Interface for the SafeExecutor contract
interface ISafeExecutor {
    /// @notice Thrown when a call to the target contract fails
    error CallFailed();

    /// @notice Thrown when the target address has no contract code
    error InvalidTarget();

    /// @notice Emitted after a successful call to the target contract
    /// @param target The address of the target contract
    /// @param result The result returned from the call
    event Executed(address indexed target, bytes result);

    /// @notice Executes a call to the target contract
    /// @param target The address of the target contract
    /// @param data The data to send to the target contract
    /// @return result The result of the call
    function execute(address target, bytes calldata data) external returns (bytes memory);
}
