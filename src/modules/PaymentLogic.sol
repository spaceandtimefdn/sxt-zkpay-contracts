// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "../libraries/AssetManagement.sol";
import {SwapLogic} from "../libraries/SwapLogic.sol";
import {PayWallLogic} from "../libraries/PayWallLogic.sol";
import {EscrowPayment} from "../libraries/EscrowPayment.sol";
import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../libraries/Constants.sol";

library PaymentLogic {
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using EscrowPayment for EscrowPayment.EscrowPaymentStorage;

    error InsufficientPayment();
    error ZeroAmountReceived();

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

    event PaymentSettled(
        address indexed asset,
        uint248 amount,
        uint248 toBePaidInSourceToken,
        uint248 receivedRefundAmount,
        uint248 receivedProtocolFeeAmount,
        bytes32 indexed transactionHash
    );

    event Authorized(
        EscrowPayment.Transaction transaction, bytes32 transactionHash, bytes32 onBehalfOf, bytes memo, bytes32 itemId
    );

    modifier _validateAsset(mapping(address asset => AssetManagement.PaymentAsset) storage _assets, address asset) {
        if (!_assets.isSupported(asset)) {
            revert AssetManagement.AssetIsNotSupportedForThisMethod();
        }
        _;
    }

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

    function _calculateProtocolFee(address asset, uint248 amount, address sxt)
        internal
        pure
        returns (uint248 protocolFeeAmount, uint248 remainingAmount)
    {
        protocolFeeAmount = asset == sxt ? 0 : uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        remainingAmount = amount - protocolFeeAmount;
    }

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

        AssetManagement.transferAssetFromCaller(asset, protocolFeeAmount, treasury);
        AssetManagement.transferAssetFromCaller(asset, transferAmount, address(this));

        uint256 receivedTargetAssetAmount =
            _swapLogicStorage.swapExactAmountIn(asset, merchant, transferAmount, merchant);

        uint248 amountInUSD = _assets.convertToUsd(asset, transferAmount);

        _validateItemPrice(_paywallLogicStorage, merchant, itemId, amountInUSD);

        emit SendPayment(
            payoutToken,
            uint248(receivedTargetAssetAmount),
            protocolFeeAmount,
            onBehalfOf,
            merchant,
            memo,
            amountInUSD,
            msg.sender,
            itemId
        );
    }

    function processSettlement(
        EscrowPayment.EscrowPaymentStorage storage _escrowPaymentStorage,
        SwapLogic.SwapLogicStorage storage _swapLogicStorage,
        mapping(address => AssetManagement.PaymentAsset) storage _assets,
        address sourceAsset,
        uint248 sourceAssetAmount,
        address from,
        address merchant,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken,
        address treasury,
        address sxt
    ) internal {
        _escrowPaymentStorage.completeAuthorizedTransaction(
            EscrowPayment.Transaction({asset: sourceAsset, amount: sourceAssetAmount, from: from, to: merchant}),
            transactionHash
        );

        address payoutToken = _swapLogicStorage.getMerchantPayoutAsset(merchant);
        (uint248 toBePaidInSourceToken, uint248 toBeRefundedInSourceToken, uint248 protocolFeeInSourceToken) =
        computeSettlementBreakdown(_assets, sourceAsset, sourceAssetAmount, maxUsdValueOfTargetToken, payoutToken, sxt);

        // pay merchant
        (uint256 receivedTargetAssetAmount) =
            _swapLogicStorage.swapExactAmountIn(sourceAsset, merchant, toBePaidInSourceToken, merchant);

        uint248 receivedRefundAmount = AssetManagement.transferAsset(sourceAsset, toBeRefundedInSourceToken, from); // refund client
        uint248 receivedProtocolFeeAmount =
            AssetManagement.transferAsset(sourceAsset, protocolFeeInSourceToken, treasury); // pay protocol

        emit PaymentSettled(
            payoutToken,
            uint248(receivedTargetAssetAmount),
            toBePaidInSourceToken,
            receivedRefundAmount,
            receivedProtocolFeeAmount,
            transactionHash
        );
    }

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
