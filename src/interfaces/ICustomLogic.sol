// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {QueryLogic} from "../libraries/QueryLogic.sol";

/// @title ICustomLogic - Interface for custom logic contract callbacks
/// @notice Custom logic contracts used to run custom logic prior to the callback to the client
/// @dev This interface is used to ensure that the custom logic contract implements the execute function
interface ICustomLogic {
    /// @notice Emitted when the custom logic is executed
    /// @param queryRequest The struct containing the query details
    /// @param queryResult The result of the query
    /// @param owner The address of the custom logic contract owner, who receives protocol rewards
    event Execute(QueryLogic.QueryRequest queryRequest, bytes queryResult, address owner);

    /// @notice Returns the address that should receive the payout
    /// @return payoutAddress The address that should receive the payout
    /// @return fee The fee that should be paid to the custom logic contract in USD with 18 decimals
    function getPayoutAddressAndFee() external view returns (address payoutAddress, uint248 fee);

    /// @notice Executes custom logic prior to the callback to the client
    /// @param queryRequest The struct containing the query details
    /// @param queryResult The result of the query
    /// @return result The result of the custom logic
    function execute(QueryLogic.QueryRequest calldata queryRequest, bytes calldata queryResult)
        external
        returns (bytes memory);
}
