// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../libraries/Constants.sol";
import {PayWallLogic} from "../libraries/PayWallLogic.sol";
import {ZKPay} from "../ZKPay.sol";
import {SwapLogic} from "../libraries/SwapLogic.sol";
import {AssetManagement} from "../libraries/AssetManagement.sol";
import {EscrowPayment} from "../libraries/EscrowPayment.sol";
import {MerchantLogic} from "../libraries/MerchantLogic.sol";

/// @title PaymentLogic
/// @notice Library for processing payments, authorizations, and settlements in the ZKPay protocol
/// @dev Orchestrates interactions between asset management, swap logic, paywall, and escrow systems
library PaymentLogic {
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using EscrowPayment for EscrowPayment.EscrowPaymentStorage;
    using MerchantLogic for mapping(address merchant => MerchantLogic.MerchantConfig);

    error InsufficientPayment();
    error ZeroAmountReceived();

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
        bytes customSourceAssetPath;
    }

    struct ProcessPaymentResult {
        address payoutToken;
        uint248 receivedProtocolFeeAmount;
        uint248 amountInUSD;
        uint256 recievedPayoutAmount;
    }

    /// @notice Processes a direct payment with asset swapping to merchant's preferred payout token
    /// @param _zkPayStorage The ZKPay storage
    /// @param params The payment parameters struct
    function processPayment(ZKPay.ZKPayStorage storage _zkPayStorage, ProcessPaymentParams memory params)
        internal
        _validateAsset(_zkPayStorage.assets, params.asset)
        returns (ProcessPaymentResult memory result)
    {
        result.payoutToken = _zkPayStorage.swapLogicStorage.getMerchantPayoutAsset(params.merchant);

        (uint248 protocolFeeAmount, uint248 transferAmount) =
            _calculateProtocolFee(params.asset, params.amount, _zkPayStorage.sxt);

        result.receivedProtocolFeeAmount =
            AssetManagement.transferAssetFromCaller(params.asset, protocolFeeAmount, _zkPayStorage.treasury);
        uint248 receivedTransferAmount =
            AssetManagement.transferAssetFromCaller(params.asset, transferAmount, address(this));

        if (receivedTransferAmount > 0) {
            MerchantLogic.MerchantConfig memory merchantConfig = _zkPayStorage.merchantLogicStorage.merchantConfigs[params.merchant];
            result.recievedPayoutAmount = _zkPayStorage.swapLogicStorage.swapExactSourceAssetAmount(
                params.asset,
                params.merchant,
                receivedTransferAmount,
                merchantConfig.payoutAddress,
                params.customSourceAssetPath
            );
        }

        result.amountInUSD = _zkPayStorage.assets.convertToUsd(params.asset, receivedTransferAmount);

        _validateItemPrice(_zkPayStorage.paywallLogicStorage, params.merchant, params.itemId, result.amountInUSD);
    }

    struct AuthorizePaymentParams {
        address asset;
        uint248 amount;
        address merchant;
        bytes32 itemId;
    }

    /// @notice Authorizes a payment by transferring assets to escrow
    /// @param _zkPayStorage The ZKPay storage
    /// @param params The payment parameters struct
    function authorizePayment(ZKPay.ZKPayStorage storage _zkPayStorage, AuthorizePaymentParams memory params)
        internal
        _validateAsset(_zkPayStorage.assets, params.asset)
        returns (EscrowPayment.Transaction memory transaction, bytes32 transactionHash)
    {
        uint248 receivedSourceAssetAmount =
            AssetManagement.transferAssetFromCaller(params.asset, params.amount, address(this));
        uint248 amountInUSD = _zkPayStorage.assets.convertToUsd(params.asset, receivedSourceAssetAmount);

        if (receivedSourceAssetAmount == 0) {
            revert ZeroAmountReceived();
        }

        _validateItemPrice(_zkPayStorage.paywallLogicStorage, params.merchant, params.itemId, amountInUSD);

        transaction = EscrowPayment.Transaction({
            asset: params.asset,
            amount: receivedSourceAssetAmount,
            from: msg.sender,
            to: params.merchant
        });

        transactionHash = EscrowPayment.authorize(_zkPayStorage.escrowPaymentStorage, transaction);
    }

    /// @notice Computes the breakdown of amounts for settlement (payment, refund, protocol fee)
    /// @param _assets The assets mapping
    /// @param sourceAsset The source asset address
    /// @param sourceAssetAmount The total source asset amount
    /// @param maxUsdValueOfTargetToken Maximum USD value allowed for the target token
    /// @param payoutToken The payout token address
    /// @param sxt The SXT token address
    /// @return toBePaidInSourceToken Amount to be paid to merchant in source token
    /// @return toBeRefundedInSourceToken Amount to be refunded to client in source token
    /// @return protocolFeeInSourceToken Protocol fee amount in source token

    function _computeSettlementBreakdown(
        mapping(address asset => AssetManagement.PaymentAsset) storage _assets,
        address sxt,
        address sourceAsset,
        uint248 sourceAssetAmount,
        uint248 maxUsdValueOfTargetToken,
        address payoutToken
    )
        internal
        view
        returns (uint248 toBePaidInSourceToken, uint248 toBeRefundedInSourceToken, uint248 protocolFeeInSourceToken)
    {
        uint248 sourceAssetInUsd = _assets.convertToUsd(sourceAsset, sourceAssetAmount);
        uint248 toBePaidInUsd =
            maxUsdValueOfTargetToken > sourceAssetInUsd ? sourceAssetInUsd : maxUsdValueOfTargetToken;

        uint248 toBePaidBeforeFee = _assets.convertUsdToToken(sourceAsset, toBePaidInUsd);
        (protocolFeeInSourceToken, toBePaidInSourceToken) = _calculateProtocolFee(payoutToken, toBePaidBeforeFee, sxt);

        toBeRefundedInSourceToken = sourceAssetAmount - toBePaidBeforeFee;

        return (toBePaidInSourceToken, toBeRefundedInSourceToken, protocolFeeInSourceToken);
    }

    // solhint-disable-next-line gas-struct-packing
    struct ProcessSettlementParams {
        address sourceAsset;
        uint248 sourceAssetAmount;
        address from;
        address merchant;
        bytes32 transactionHash;
        uint248 maxUsdValueOfTargetToken;
    }

    struct ProcessSettlementResult {
        address payoutToken;
        uint256 receivedTargetAssetAmount;
        uint248 receivedRefundAmount;
        uint248 receivedProtocolFeeAmount;
    }

    /// @notice Settles an escrowed payment by
    /// - completing the authorized transaction
    /// - computing the settlement breakdown
    /// - paying the merchant
    /// - refunding the client
    /// - paying the protocol fee
    /// @param _zkPayStorage The ZKPay storage
    /// @param params The settlement parameters struct
    function processSettlement(ZKPay.ZKPayStorage storage _zkPayStorage, ProcessSettlementParams memory params)
        internal
        returns (ProcessSettlementResult memory result)
    {
        _zkPayStorage.escrowPaymentStorage.completeAuthorizedTransaction(
            EscrowPayment.Transaction({
                asset: params.sourceAsset,
                amount: params.sourceAssetAmount,
                from: params.from,
                to: params.merchant
            }),
            params.transactionHash
        );

        result.payoutToken = _zkPayStorage.swapLogicStorage.getMerchantPayoutAsset(params.merchant);
        (uint248 toBePaidInSourceToken, uint248 toBeRefundedInSourceToken, uint248 protocolFeeInSourceToken) =
        _computeSettlementBreakdown(
            _zkPayStorage.assets,
            _zkPayStorage.sxt,
            params.sourceAsset,
            params.sourceAssetAmount,
            params.maxUsdValueOfTargetToken,
            result.payoutToken
        );

        // 1. pay merchant
        // slither-disable-next-line reentrancy-events
        MerchantLogic.MerchantConfig memory merchantConfig = _zkPayStorage.merchantLogicStorage.merchantConfigs[params.merchant];
        result.receivedTargetAssetAmount = _zkPayStorage.swapLogicStorage.swapExactSourceAssetAmount(
            params.sourceAsset, params.merchant, toBePaidInSourceToken, merchantConfig.payoutAddress, ""
        );

        // 2. refund client
        result.receivedRefundAmount =
            AssetManagement.transferAsset(params.sourceAsset, toBeRefundedInSourceToken, params.from);

        // 3. pay protocol
        result.receivedProtocolFeeAmount =
            AssetManagement.transferAsset(params.sourceAsset, protocolFeeInSourceToken, _zkPayStorage.treasury);
    }
}
