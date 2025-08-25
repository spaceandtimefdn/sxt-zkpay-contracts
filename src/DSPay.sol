// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IDSPay} from "./interfaces/IDSPay.sol";
import {AssetManagement} from "./libraries/AssetManagement.sol";
import {MerchantLogic} from "./libraries/MerchantLogic.sol";
import {SwapLogic} from "./libraries/SwapLogic.sol";
import {PayWallLogic} from "./libraries/PayWallLogic.sol";
import {SafeExecutor} from "./SafeExecutor.sol";
import {IMerchantCallback} from "./interfaces/IMerchantCallback.sol";
import {PendingPayment} from "./libraries/PendingPayment.sol";
import {PaymentLogic} from "./module/PaymentLogic.sol";

// slither-disable-next-line locked-ether
contract DSPay is IDSPay, AccessControlDefaultAdminRules, ReentrancyGuard {
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using MerchantLogic for MerchantLogic.MerchantLogicStorage;
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using PendingPayment for PendingPayment.PendingPaymentStorage;

    error InsufficientPayment();
    error ExecutorAddressCannotBeZero();
    error InvalidMerchant();
    error ZeroAmountReceived();
    error InvalidItemId();
    error ItemIdCallbackNotConfigured();
    error InvalidCallbackContract();

    struct PaymentMetadata {
        address payoutToken;
        uint256 payoutAmount;
        uint248 amountInUSD;
        bytes32 onBehalfOf;
        address sender;
        bytes32 itemId;
    }

    struct SendWithCallbackParams {
        address asset;
        uint248 amount;
        bytes32 onBehalfOf;
        address merchant;
        bytes32 itemId;
        bytes callbackData;
        bytes customSourceAssetPath;
    }

    // solhint-disable-next-line gas-struct-packing
    struct DSPayStorage {
        address executorAddress;
        mapping(address asset => AssetManagement.PaymentAsset) assets;
        MerchantLogic.MerchantLogicStorage merchantLogicStorage;
        SwapLogic.SwapLogicStorage swapLogicStorage;
        PayWallLogic.PayWallLogicStorage paywallLogicStorage;
        PendingPayment.PendingPaymentStorage pendingPaymentStorage;
    }

    DSPayStorage internal _dsPayStorage;

    constructor(address admin, SwapLogic.SwapLogicConfig memory swapLogicConfig)
        AccessControlDefaultAdminRules(0, admin)
    {
        _deployExecutor();
        _dsPayStorage.swapLogicStorage.setConfig(swapLogicConfig);
    }

    function _deployExecutor() internal {
        _dsPayStorage.executorAddress = address(new SafeExecutor());
    }

    /// @inheritdoc IDSPay
    function getExecutorAddress() external view returns (address executor) {
        return _dsPayStorage.executorAddress;
    }

    /// @inheritdoc IDSPay
    function setPaymentAsset(
        address assetAddress,
        AssetManagement.PaymentAsset calldata paymentAsset,
        bytes calldata path
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address originAsset = SwapLogic.calldataExtractPathOriginAsset(path);
        if (originAsset != assetAddress) {
            revert SwapLogic.InvalidPath();
        }

        AssetManagement.set(_dsPayStorage.assets, assetAddress, paymentAsset);
        _dsPayStorage.swapLogicStorage.setSourceAssetPath(path);
    }

    /// @inheritdoc IDSPay
    function removePaymentAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AssetManagement.remove(_dsPayStorage.assets, asset);
    }

    /// @inheritdoc IDSPay
    function getPaymentAsset(address asset) external view returns (AssetManagement.PaymentAsset memory paymentAsset) {
        return AssetManagement.get(_dsPayStorage.assets, asset);
    }

    function _validateMerchant(address merchant, address callbackContractAddress) internal view {
        address callbackContractMerchant = IMerchantCallback(callbackContractAddress).getMerchant();
        if (callbackContractMerchant != merchant) {
            revert InvalidMerchant();
        }
    }

    function _sendPayment(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId,
        bytes memory customSourceAssetPath
    ) internal returns (PaymentLogic.ProcessPaymentResult memory result) {
        result = PaymentLogic.processPayment(
            _dsPayStorage,
            PaymentLogic.ProcessPaymentParams({
                asset: asset,
                amount: amount,
                merchant: merchant,
                itemId: itemId,
                customSourceAssetPath: customSourceAssetPath
            })
        );

        emit SendPayment(asset, amount, onBehalfOf, merchant, memo, result.amountInUSD, msg.sender, itemId);
    }

    /// @inheritdoc IDSPay
    function send(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external nonReentrant {
        _sendPayment(asset, amount, onBehalfOf, merchant, memo, itemId, "");
    }

    /// @inheritdoc IDSPay
    function sendPathOverride(
        bytes calldata customSourceAssetPath,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external nonReentrant {
        _sendPayment(
            SwapLogic.calldataExtractPathOriginAsset(customSourceAssetPath),
            amount,
            onBehalfOf,
            merchant,
            memo,
            itemId,
            customSourceAssetPath
        );
    }

    function _sendWithCallback(SendWithCallbackParams memory params, bytes calldata memo) internal {
        if (params.itemId == bytes32(0)) {
            revert InvalidItemId();
        }

        MerchantLogic.ItemIdCallbackConfig memory callbackConfig =
            _dsPayStorage.merchantLogicStorage.getItemIdCallback(params.merchant, params.itemId);

        if (callbackConfig.contractAddress == address(0)) {
            revert ItemIdCallbackNotConfigured();
        }

        PaymentLogic.ProcessPaymentResult memory result = _sendPayment(
            params.asset,
            params.amount,
            params.onBehalfOf,
            params.merchant,
            memo,
            params.itemId,
            params.customSourceAssetPath
        );

        _validateMerchant(params.merchant, callbackConfig.contractAddress);

        bytes memory fullCallbackData;
        if (callbackConfig.includePaymentMetadata) {
            PaymentMetadata memory metadata = PaymentMetadata({
                payoutToken: result.payoutToken,
                payoutAmount: result.receivedPayoutAmount,
                amountInUSD: result.amountInUSD,
                onBehalfOf: params.onBehalfOf,
                sender: msg.sender,
                itemId: params.itemId
            });

            // slither-disable-next-line encode-packed-collision
            fullCallbackData = abi.encodePacked(callbackConfig.funcSig, abi.encode(metadata), params.callbackData);
        } else {
            fullCallbackData = abi.encodePacked(callbackConfig.funcSig, params.callbackData);
        }

        SafeExecutor(_dsPayStorage.executorAddress).execute(callbackConfig.contractAddress, fullCallbackData);
    }

    /// @inheritdoc IDSPay
    function sendWithCallbackPathOverride(
        bytes calldata customSourceAssetPath,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId,
        bytes calldata callbackData
    ) external nonReentrant {
        _sendWithCallback(
            SendWithCallbackParams({
                asset: SwapLogic.calldataExtractPathOriginAsset(customSourceAssetPath),
                amount: amount,
                onBehalfOf: onBehalfOf,
                merchant: merchant,
                itemId: itemId,
                callbackData: callbackData,
                customSourceAssetPath: customSourceAssetPath
            }),
            memo
        );
    }

    /// @inheritdoc IDSPay
    function sendWithCallback(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId,
        bytes calldata callbackData
    ) external nonReentrant {
        _sendWithCallback(
            SendWithCallbackParams({
                asset: asset,
                amount: amount,
                onBehalfOf: onBehalfOf,
                merchant: merchant,
                itemId: itemId,
                callbackData: callbackData,
                customSourceAssetPath: ""
            }),
            memo
        );
    }

    function _authorize(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) internal {
        PaymentLogic.AuthorizePaymentParams memory params =
            PaymentLogic.AuthorizePaymentParams({asset: asset, amount: amount, merchant: merchant, itemId: itemId});

        (PendingPayment.Transaction memory transaction, bytes32 transactionHash) =
            PaymentLogic.authorizePayment(_dsPayStorage, params);

        emit Authorized(transaction, transactionHash, onBehalfOf, memo, itemId);
    }

    /// @inheritdoc IDSPay
    function authorize(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external nonReentrant {
        _authorize(asset, amount, onBehalfOf, merchant, memo, itemId);
    }

    /// @inheritdoc IDSPay
    function authorizeWithCallback(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        address callbackContractAddress,
        bytes calldata callbackData
    ) external nonReentrant {
        bytes4 selector = bytes4(callbackData[:4]);
        bytes32 itemId = keccak256(abi.encode(callbackContractAddress, selector));

        _authorize(asset, amount, onBehalfOf, merchant, memo, itemId);

        SafeExecutor(_dsPayStorage.executorAddress).execute(callbackContractAddress, callbackData);
    }

    /// @inheritdoc IDSPay
    function setMerchantConfig(MerchantLogic.MerchantConfig calldata config, bytes calldata path) external {
        _dsPayStorage.merchantLogicStorage.setConfig(msg.sender, config);
        _dsPayStorage.swapLogicStorage.setMerchantTargetAssetPath(msg.sender, path);
    }

    /// @inheritdoc IDSPay
    function getMerchantConfig(address merchant) external view returns (MerchantLogic.MerchantConfig memory config) {
        return _dsPayStorage.merchantLogicStorage.getConfig(merchant);
    }

    /// @inheritdoc IDSPay
    function setPaywallItemPrice(bytes32 item, uint248 price) external {
        _dsPayStorage.paywallLogicStorage.setItemPrice(msg.sender, item, price);
    }

    /// @inheritdoc IDSPay
    function getPaywallItemPrice(bytes32 item, address merchant) external view returns (uint248 price) {
        return _dsPayStorage.paywallLogicStorage.getItemPrice(merchant, item);
    }

    function _settleAuthorizedPayment(
        bytes memory customSourceAssetPath,
        address sourceAsset,
        uint248 sourceAssetAmount,
        address from,
        address merchant,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken
    ) internal {
        PaymentLogic.ProcessSettlementResult memory result = PaymentLogic.processSettlement(
            _dsPayStorage,
            PaymentLogic.ProcessSettlementParams({
                customSourceAssetPath: customSourceAssetPath,
                sourceAsset: sourceAsset,
                sourceAssetAmount: sourceAssetAmount,
                from: from,
                merchant: merchant,
                transactionHash: transactionHash,
                maxUsdValueOfTargetToken: maxUsdValueOfTargetToken
            })
        );

        emit AuthorizedPaymentSettled(
            sourceAsset,
            sourceAssetAmount,
            result.payoutToken,
            result.receivedTargetAssetAmount,
            result.receivedRefundAmount,
            from,
            merchant,
            transactionHash
        );
    }

    /// @inheritdoc IDSPay
    function settleAuthorizedPayment(
        address sourceAsset,
        uint248 sourceAssetAmount,
        address from,
        address merchant,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken
    ) external nonReentrant {
        _settleAuthorizedPayment(
            "", sourceAsset, sourceAssetAmount, from, merchant, transactionHash, maxUsdValueOfTargetToken
        );
    }

    /// @inheritdoc IDSPay
    function settleAuthorizedPaymentPathOverride(
        bytes calldata customSourceAssetPath,
        uint248 sourceAssetAmount,
        address from,
        address merchant,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken
    ) external nonReentrant {
        address sourceAsset = SwapLogic.calldataExtractPathOriginAsset(customSourceAssetPath);

        _settleAuthorizedPayment(
            customSourceAssetPath,
            sourceAsset,
            sourceAssetAmount,
            from,
            merchant,
            transactionHash,
            maxUsdValueOfTargetToken
        );
    }

    function setItemIdCallbackConfig(bytes32 itemId, MerchantLogic.ItemIdCallbackConfig calldata config) external {
        if (itemId == bytes32(0)) {
            revert InvalidItemId();
        }
        if (config.contractAddress == address(0)) {
            revert InvalidCallbackContract();
        }
        _dsPayStorage.merchantLogicStorage.setItemIdCallback(msg.sender, itemId, config);
    }

    function getItemIdCallbackConfig(address merchant, bytes32 itemId)
        external
        view
        returns (MerchantLogic.ItemIdCallbackConfig memory config)
    {
        return _dsPayStorage.merchantLogicStorage.getItemIdCallback(merchant, itemId);
    }
}
