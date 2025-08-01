// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "../libraries/AssetManagement.sol";
import {SwapLogic} from "../libraries/SwapLogic.sol";
import {PayWallLogic} from "../libraries/PayWallLogic.sol";
import {EscrowPayment} from "../libraries/EscrowPayment.sol";
import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../libraries/Constants.sol";

/// @title PaymentLogic
/// @notice Library for processing payments, authorizations, and settlements in the ZKPay protocol
/// @dev Orchestrates interactions between asset management, swap logic, paywall, and escrow systems
library PaymentLogic {
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using EscrowPayment for EscrowPayment.EscrowPaymentStorage;

    /// @notice Error thrown when payment amount is insufficient for the requested item
    error InsufficientPayment();
    /// @notice Error thrown when zero amount is received during transfer
    error ZeroAmountReceived();

    /// @notice Emitted when a payment is successfully processed
    /// @param asset The payout token address
    /// @param amount The amount paid to merchant in payout token
    /// @param protocolFeeAmount The protocol fee amount deducted
    /// @param onBehalfOf The identifier for whom the payment is made
    /// @param merchant The merchant receiving the payment
    /// @param memo Additional payment information
    /// @param amountInUSD The payment amount in USD
    /// @param from The address initiating the payment
    /// @param itemId The identifier of the purchased item
    event SendPayment(
        address indexed asset,
        uint248 amount,
        uint248 protocolFeeAmount,
        bytes32 indexed onBehalfOf,
        address indexed merchant,
        bytes memo,
        uint248 amountInUSD,
        address from,
        bytes32 itemId
    );

    /// @notice Emitted when an escrowed payment is settled
    /// @param asset The payout token address
    /// @param amount The amount paid to merchant in payout token
    /// @param toBePaidInSourceToken Amount used for payment in source token
    /// @param receivedRefundAmount Amount refunded to the client
    /// @param receivedProtocolFeeAmount Protocol fee amount collected
    /// @param transactionHash The hash of the settled transaction
    event PaymentSettled(
        address indexed asset,
        uint248 amount,
        uint248 toBePaidInSourceToken,
        uint248 receivedRefundAmount,
        uint248 receivedProtocolFeeAmount,
        bytes32 indexed transactionHash
    );

    /// @notice Emitted when a payment is authorized and held in escrow
    /// @param transaction The transaction details
    /// @param transactionHash The hash of the authorized transaction
    /// @param onBehalfOf The identifier for whom the payment is made
    /// @param memo Additional payment information
    /// @param itemId The identifier of the purchased item
    event Authorized(
        EscrowPayment.Transaction transaction, bytes32 transactionHash, bytes32 onBehalfOf, bytes memo, bytes32 itemId
    );

    /// @notice Modifier to validate that an asset is supported for payment operations
    /// @param _assets The assets mapping
    /// @param asset The asset address to validate
    modifier _validateAsset(mapping(address asset => AssetManagement.PaymentAsset) storage _assets, address asset) {
        if (!_assets.isSupported(asset)) {
            revert AssetManagement.AssetIsNotSupportedForThisMethod();
        }
        _;
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

    /// @notice Processes a direct payment with asset swapping to merchant's preferred payout token
    /// @param _swapLogicStorage The swap logic storage
    /// @param _assets The assets mapping
    /// @param _paywallLogicStorage The paywall logic storage
    /// @param asset The payment asset address
    /// @param amount The payment amount
    /// @param onBehalfOf The identifier for whom the payment is made
    /// @param merchant The merchant receiving the payment
    /// @param memo Additional payment information
    /// @param itemId The identifier of the purchased item
    /// @param treasury The treasury address for protocol fees
    /// @param sxt The SXT token address
    function processPayment(
        SwapLogic.SwapLogicStorage storage _swapLogicStorage,
        mapping(address asset => AssetManagement.PaymentAsset) storage _assets,
        PayWallLogic.PayWallLogicStorage storage _paywallLogicStorage,
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId,
        address treasury,
        address sxt
    ) internal _validateAsset(_assets, asset) {
        address payoutToken = _swapLogicStorage.getMerchantPayoutAsset(merchant);

        uint248 protocolFeeAmount;
        uint248 transferAmount;
        (protocolFeeAmount, transferAmount) = _calculateProtocolFee(asset, amount, sxt);

        uint248 receivedProtocolFeeAmount = AssetManagement.transferAssetFromCaller(asset, protocolFeeAmount, treasury);
        uint248 receivedTransferAmount = AssetManagement.transferAssetFromCaller(asset, transferAmount, address(this));

        uint256 receivedTargetAssetAmount = 0;

        if (receivedTransferAmount > 0) {
            // slither-disable-next-line reentrancy-events
            receivedTargetAssetAmount =
                _swapLogicStorage.swapExactSourceAssetAmount(asset, merchant, receivedTransferAmount, merchant);
        }

        uint248 amountInUSD = _assets.convertToUsd(asset, receivedTransferAmount);

        _validateItemPrice(_paywallLogicStorage, merchant, itemId, amountInUSD);

        emit SendPayment(
            payoutToken,
            uint248(receivedTargetAssetAmount),
            receivedProtocolFeeAmount,
            onBehalfOf,
            merchant,
            memo,
            amountInUSD,
            msg.sender,
            itemId
        );
    }

    /// @notice Settles an escrowed payment by completing the authorized transaction
    /// @param _escrowPaymentStorage The escrow payment storage
    /// @param _swapLogicStorage The swap logic storage
    /// @param _assets The assets mapping
    /// @param treasury The treasury address for protocol fees
    /// @param sxt The SXT token address
    /// @param sourceAsset The source asset address
    /// @param sourceAssetAmount The source asset amount
    /// @param from The original sender address
    /// @param merchant The merchant receiving the payment
    /// @param transactionHash The transaction hash to settle
    /// @param maxUsdValueOfTargetToken Maximum USD value allowed for the target token
    function processSettlement(
        EscrowPayment.EscrowPaymentStorage storage _escrowPaymentStorage,
        SwapLogic.SwapLogicStorage storage _swapLogicStorage,
        mapping(address => AssetManagement.PaymentAsset) storage _assets,
        address treasury,
        address sxt,
        address sourceAsset,
        uint248 sourceAssetAmount,
        address from,
        address merchant,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken
    ) internal {
        _escrowPaymentStorage.completeAuthorizedTransaction(
            EscrowPayment.Transaction({asset: sourceAsset, amount: sourceAssetAmount, from: from, to: merchant}),
            transactionHash
        );

        address payoutToken = _swapLogicStorage.getMerchantPayoutAsset(merchant);
        (uint248 toBePaidInSourceToken, uint248 toBeRefundedInSourceToken, uint248 protocolFeeInSourceToken) =
        computeSettlementBreakdown(_assets, sourceAsset, sourceAssetAmount, maxUsdValueOfTargetToken, payoutToken, sxt);

        // 1. pay merchant
        // slither-disable-next-line reentrancy-events
        (uint256 receivedTargetAssetAmount) =
            _swapLogicStorage.swapExactSourceAssetAmount(sourceAsset, merchant, toBePaidInSourceToken, merchant);

        // 2. refund client
        uint248 receivedRefundAmount = AssetManagement.transferAsset(sourceAsset, toBeRefundedInSourceToken, from);

        // 3. pay protocol
        uint248 receivedProtocolFeeAmount =
            AssetManagement.transferAsset(sourceAsset, protocolFeeInSourceToken, treasury);

        emit PaymentSettled(
            payoutToken,
            uint248(receivedTargetAssetAmount),
            toBePaidInSourceToken,
            receivedRefundAmount,
            receivedProtocolFeeAmount,
            transactionHash
        );
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
    function computeSettlementBreakdown(
        mapping(address asset => AssetManagement.PaymentAsset) storage _assets,
        address sourceAsset,
        uint248 sourceAssetAmount,
        uint248 maxUsdValueOfTargetToken,
        address payoutToken,
        address sxt
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

    /// @notice Authorizes a payment by transferring assets to escrow and validating the transaction
    /// @param _escrowPaymentStorage The escrow payment storage
    /// @param _assets The assets mapping
    /// @param _paywallLogicStorage The paywall logic storage
    /// @param asset The payment asset address
    /// @param amount The payment amount
    /// @param onBehalfOf The identifier for whom the payment is made
    /// @param merchant The merchant receiving the payment
    /// @param memo Additional payment information
    /// @param itemId The identifier of the purchased item
    /// @return transactionHash The hash of the authorized transaction
    function authorizePayment(
        EscrowPayment.EscrowPaymentStorage storage _escrowPaymentStorage,
        mapping(address asset => AssetManagement.PaymentAsset) storage _assets,
        PayWallLogic.PayWallLogicStorage storage _paywallLogicStorage,
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) internal _validateAsset(_assets, asset) returns (bytes32 transactionHash) {
        uint248 actualAmountReceived = AssetManagement.transferAssetFromCaller(asset, amount, address(this));
        uint248 amountInUSD = _assets.convertToUsd(asset, actualAmountReceived);

        if (actualAmountReceived == 0) {
            revert ZeroAmountReceived();
        }

        _validateItemPrice(_paywallLogicStorage, merchant, itemId, amountInUSD);

        EscrowPayment.Transaction memory transaction =
            EscrowPayment.Transaction({asset: asset, amount: actualAmountReceived, from: msg.sender, to: merchant});

        transactionHash = EscrowPayment.authorize(_escrowPaymentStorage, transaction);

        emit Authorized(transaction, transactionHash, onBehalfOf, memo, itemId);
    }
}
