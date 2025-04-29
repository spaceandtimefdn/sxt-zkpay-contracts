// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IZKPayClient - Interface for ZKpay client contract callbacks
/// @notice Client contracts implement this interface to utilize the ZKpay protocol. The methods defined here are
/// callbacks that are required by the protocol to handle query results and error handling.
interface IZKPayClient {
    /**
     * @notice Callback function for handling successful query results.
     * @dev This function is invoked by the ZKpay contract upon successful fulfillment of a query.
     * @param queryHash The unique identifier for the query.
     * @param queryResult The result of the query.
     * @param callbackData Additional data that was originally passed with the query.
     */
    function zkPayCallback(bytes32 queryHash, bytes calldata queryResult, bytes calldata callbackData) external;
}
