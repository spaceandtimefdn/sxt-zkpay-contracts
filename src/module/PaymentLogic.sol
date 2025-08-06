// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../libraries/Constants.sol";

/// @title PaymentLogic
/// @notice Library for processing payments, authorizations, and settlements in the ZKPay protocol
/// @dev Orchestrates interactions between asset management, swap logic, paywall, and escrow systems
library PaymentLogic {
    /// @notice Calculates the protocol fee and remaining amount after fee deduction
    /// @param asset The asset address being processed
    /// @param amount The total amount to process
    /// @param sxt The SXT token address (no fee charged for SXT payments)
    /// @return protocolFeeAmount The calculated protocol fee
    /// @return remainingAmount The amount remaining after fee deduction
    function _calculateProtocolFee(address asset, uint248 amount, address sxt)
        internal
        pure
        returns (uint248 protocolFeeAmount, uint248 remainingAmount)
    {
        protocolFeeAmount = asset == sxt ? 0 : uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        remainingAmount = amount - protocolFeeAmount;
    }
}
