// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../libraries/Constants.sol";
import {PayWallLogic} from "../libraries/PayWallLogic.sol";
import {ZKPay} from "../ZKPay.sol";
import {SwapLogic} from "../libraries/SwapLogic.sol";
import {AssetManagement} from "../libraries/AssetManagement.sol";

/// @title PaymentLogic
/// @notice Library for processing payments, authorizations, and settlements in the ZKPay protocol
/// @dev Orchestrates interactions between asset management, swap logic, paywall, and escrow systems
library PaymentLogic {
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using SwapLogic for SwapLogic.SwapLogicStorage;

    error InsufficientPayment();

    /// @notice Modifier to validate that an asset is supported for payment operations
    /// @param _assets The assets mapping
    /// @param asset The asset address to validate
    modifier _validateAsset(mapping(address asset => AssetManagement.PaymentAsset) storage _assets, address asset) {
        if (!_assets.isSupported(asset)) {
            revert AssetManagement.AssetIsNotSupportedForThisMethod();
        }
        _;
    }

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

    /// @notice Validates that the payment amount meets the minimum item price requirement
    /// @param _paywallLogicStorage The paywall logic storage
    /// @param merchant The merchant address
    /// @param itemId The item identifier
    /// @param amountInUSD The payment amount in USD
    function _validateItemPrice(
        PayWallLogic.PayWallLogicStorage storage _paywallLogicStorage,
        address merchant,
        bytes32 itemId,
        uint248 amountInUSD
    ) internal view {
        uint248 itemPrice = _paywallLogicStorage.getItemPrice(merchant, itemId);
        if (amountInUSD < itemPrice) {
            revert InsufficientPayment();
        }
    }

    /// @notice Parameters for processing a payment
    /// @param asset The source asset being processed
    /// @param amount Source asset amount being processed
    /// @param merchant The merchant address
    /// @param itemId The item identifier
    struct ProcessPaymentParams {
        address asset;
        uint248 amount;
        address merchant;
        bytes32 itemId;
    }

    /// @notice Processes a direct payment with asset swapping to merchant's preferred payout token
    /// @param _zkPayStorage The ZKPay storage
    /// @param params The payment parameters struct
    function processPayment(ZKPay.ZKPayStorage storage _zkPayStorage, ProcessPaymentParams memory params)
        internal
        _validateAsset(_zkPayStorage.assets, params.asset)
        returns (
            address payoutToken,
            uint248 receivedProtocolFeeAmount,
            uint248 amountInUSD,
            uint256 recievedPayoutAmount
        )
    {
        payoutToken = _zkPayStorage.swapLogicStorage.getMerchantPayoutAsset(params.merchant);

        (uint248 protocolFeeAmount, uint248 transferAmount) =
            _calculateProtocolFee(params.asset, params.amount, _zkPayStorage.sxt);

        receivedProtocolFeeAmount =
            AssetManagement.transferAssetFromCaller(params.asset, protocolFeeAmount, _zkPayStorage.treasury);
        uint248 receivedTransferAmount =
            AssetManagement.transferAssetFromCaller(params.asset, transferAmount, address(this));

        if (receivedTransferAmount > 0) {
            recievedPayoutAmount = _zkPayStorage.swapLogicStorage.swapExactSourceAssetAmount(
                params.asset, params.merchant, receivedTransferAmount, params.merchant
            );
        }

        amountInUSD = _zkPayStorage.assets.convertToUsd(params.asset, receivedTransferAmount);

        _validateItemPrice(_zkPayStorage.paywallLogicStorage, params.merchant, params.itemId, amountInUSD);
    }
}
