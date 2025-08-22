// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IZKPay} from "./interfaces/IZKPay.sol";
import {AssetManagement} from "./libraries/AssetManagement.sol";
import {MerchantLogic} from "./libraries/MerchantLogic.sol";
import {ZERO_ADDRESS} from "./libraries/Constants.sol";
import {SwapLogic} from "./libraries/SwapLogic.sol";
import {PayWallLogic} from "./libraries/PayWallLogic.sol";
import {SafeExecutor} from "./SafeExecutor.sol";
import {IMerchantCallback} from "./interfaces/IMerchantCallback.sol";
import {EscrowPayment} from "./libraries/EscrowPayment.sol";
import {PaymentLogic} from "./module/PaymentLogic.sol";

// slither-disable-next-line locked-ether
contract ZKPay is IZKPay, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using MerchantLogic for MerchantLogic.MerchantLogicStorage;
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using EscrowPayment for EscrowPayment.EscrowPaymentStorage;

    error TreasuryAddressCannotBeZero();
    error TreasuryAddressSameAsCurrent();
    error SXTAddressCannotBeZero();
    error InsufficientPayment();
    error ExecutorAddressCannotBeZero();
    error InvalidMerchant();
    error ZeroAmountReceived();
    error InvalidItemId();
    error ItemIdCallbackNotConfigured();
    error InvalidCallbackContract();

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
    struct ZKPayStorage {
        address sxt;
        address treasury;
        address executorAddress;
        mapping(address asset => AssetManagement.PaymentAsset) assets;
        MerchantLogic.MerchantLogicStorage merchantLogicStorage;
        SwapLogic.SwapLogicStorage swapLogicStorage;
        PayWallLogic.PayWallLogicStorage paywallLogicStorage;
        EscrowPayment.EscrowPaymentStorage escrowPaymentStorage;
    }

    ZKPayStorage internal _zkPayStorage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        address treasury,
        address sxt,
        SwapLogic.SwapLogicConfig calldata swapLogicConfig
    ) external initializer {
        __Ownable_init(owner);
        __ReentrancyGuard_init();
        _setTreasury(treasury);
        _setSXT(sxt);
        _deployExecutor();

        _zkPayStorage.swapLogicStorage.setConfig(swapLogicConfig);
    }

    function _deployExecutor() internal {
        _zkPayStorage.executorAddress = address(new SafeExecutor());
    }

    function _setSXT(address sxt) internal {
        if (sxt == ZERO_ADDRESS) {
            revert SXTAddressCannotBeZero();
        }
        _zkPayStorage.sxt = sxt;
    }

    function _setTreasury(address treasury) internal {
        if (treasury == ZERO_ADDRESS) {
            revert TreasuryAddressCannotBeZero();
        }

        if (treasury == _zkPayStorage.treasury) {
            revert TreasuryAddressSameAsCurrent();
        }

        _zkPayStorage.treasury = treasury;
        emit TreasurySet(treasury);
    }

    /// @inheritdoc IZKPay
    function setTreasury(address treasury) external onlyOwner {
        _setTreasury(treasury);
    }

    /// @inheritdoc IZKPay
    function getTreasury() external view returns (address treasury) {
        return _zkPayStorage.treasury;
    }

    /// @inheritdoc IZKPay
    function getSXT() external view returns (address sxt) {
        return _zkPayStorage.sxt;
    }

    /// @inheritdoc IZKPay
    function getExecutorAddress() external view returns (address executor) {
        return _zkPayStorage.executorAddress;
    }

    /// @inheritdoc IZKPay
    function setPaymentAsset(
        address assetAddress,
        AssetManagement.PaymentAsset calldata paymentAsset,
        bytes calldata path
    ) external onlyOwner {
        address originAsset = SwapLogic.calldataExtractPathOriginAsset(path);
        if (originAsset != assetAddress) {
            revert SwapLogic.InvalidPath();
        }

        AssetManagement.set(_zkPayStorage.assets, assetAddress, paymentAsset);
        _zkPayStorage.swapLogicStorage.setSourceAssetPath(path);
    }

    /// @inheritdoc IZKPay
    function removePaymentAsset(address asset) external onlyOwner {
        AssetManagement.remove(_zkPayStorage.assets, asset);
    }

    /// @inheritdoc IZKPay
    function getPaymentAsset(address asset) external view returns (AssetManagement.PaymentAsset memory paymentAsset) {
        return AssetManagement.get(_zkPayStorage.assets, asset);
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
    ) internal {
        PaymentLogic.ProcessPaymentResult memory result = PaymentLogic.processPayment(
            _zkPayStorage,
            PaymentLogic.ProcessPaymentParams({
                asset: asset,
                amount: amount,
                merchant: merchant,
                itemId: itemId,
                customSourceAssetPath: customSourceAssetPath
            })
        );

        emit SendPayment(
            asset,
            amount,
            result.receivedProtocolFeeAmount,
            onBehalfOf,
            merchant,
            memo,
            result.amountInUSD,
            msg.sender,
            itemId
        );
    }

    /// @inheritdoc IZKPay
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

    /// @inheritdoc IZKPay
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
            MerchantLogic.getItemIdCallback(_zkPayStorage.merchantLogicStorage, params.merchant, params.itemId);

        if (callbackConfig.contractAddress == address(0)) {
            revert ItemIdCallbackNotConfigured();
        }

        _sendPayment(
            params.asset,
            params.amount,
            params.onBehalfOf,
            params.merchant,
            memo,
            params.itemId,
            params.customSourceAssetPath
        );
        _validateMerchant(params.merchant, callbackConfig.contractAddress);

        bytes memory fullCallbackData = abi.encodePacked(callbackConfig.funcSig, params.callbackData);
        SafeExecutor(_zkPayStorage.executorAddress).execute(callbackConfig.contractAddress, fullCallbackData);
    }

    /// @inheritdoc IZKPay
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

    /// @inheritdoc IZKPay
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

        (EscrowPayment.Transaction memory transaction, bytes32 transactionHash) =
            PaymentLogic.authorizePayment(_zkPayStorage, params);

        emit Authorized(transaction, transactionHash, onBehalfOf, memo, itemId);
    }

    /// @inheritdoc IZKPay
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

    /// @inheritdoc IZKPay
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

        SafeExecutor(_zkPayStorage.executorAddress).execute(callbackContractAddress, callbackData);
    }

    /// @inheritdoc IZKPay
    function setMerchantConfig(MerchantLogic.MerchantConfig calldata config, bytes calldata path) external {
        _zkPayStorage.merchantLogicStorage.set(msg.sender, config);
        _zkPayStorage.swapLogicStorage.setMerchantTargetAssetPath(msg.sender, path);
    }

    /// @inheritdoc IZKPay
    function getMerchantConfig(address merchant) external view returns (MerchantLogic.MerchantConfig memory config) {
        return _zkPayStorage.merchantLogicStorage.get(merchant);
    }

    /// @inheritdoc IZKPay
    function setPaywallItemPrice(bytes32 item, uint248 price) external {
        _zkPayStorage.paywallLogicStorage.setItemPrice(msg.sender, item, price);
    }

    /// @inheritdoc IZKPay
    function getPaywallItemPrice(bytes32 item, address merchant) external view returns (uint248 price) {
        return _zkPayStorage.paywallLogicStorage.getItemPrice(merchant, item);
    }

    /// @inheritdoc IZKPay
    function settleAuthorizedPayment(
        address sourceAsset,
        uint248 sourceAssetAmount,
        address from,
        address merchant,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken
    ) external nonReentrant {
        PaymentLogic.ProcessSettlementResult memory result = PaymentLogic.processSettlement(
            _zkPayStorage,
            PaymentLogic.ProcessSettlementParams({
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
            result.receivedProtocolFeeAmount,
            from,
            merchant,
            transactionHash
        );
    }

    function setItemIdCallbackConfig(bytes32 itemId, MerchantLogic.ItemIdCallbackConfig calldata config) external {
        if (itemId == bytes32(0)) {
            revert InvalidItemId();
        }
        if (config.contractAddress == address(0)) {
            revert InvalidCallbackContract();
        }
        MerchantLogic.setItemIdCallback(_zkPayStorage.merchantLogicStorage, msg.sender, itemId, config);
    }

    function getItemIdCallbackConfig(bytes32 itemId)
        external
        view
        returns (MerchantLogic.ItemIdCallbackConfig memory config)
    {
        return MerchantLogic.getItemIdCallback(_zkPayStorage.merchantLogicStorage, msg.sender, itemId);
    }
}
