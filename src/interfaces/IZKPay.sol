// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "../libraries/AssetManagement.sol";
import {MerchantLogic} from "../libraries/MerchantLogic.sol";
import {EscrowPayment} from "../libraries/EscrowPayment.sol";

interface IZKPay {
    /// @notice Emitted when the treasury address is set
    /// @param treasury The new treasury address
    event TreasurySet(address indexed treasury);

    /// @notice Emitted when a payment is made
    /// @param asset The asset used for payment
    /// @param amount The amount of tokens used for payment
    /// @param protocolFeeAmount The amount of protocol fee in source token.
    /// @param onBehalfOf The identifier on whose behalf the payment was made
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param amountInUSD The amount in USD
    /// @param sender The address that initiated the payment
    /// @param itemId The item ID
    event SendPayment(
        address indexed asset,
        uint248 amount,
        uint248 protocolFeeAmount,
        bytes32 onBehalfOf,
        address indexed merchant,
        bytes memo,
        uint248 amountInUSD,
        address indexed sender,
        bytes32 itemId
    );

    /// @notice Emitted when a payment is authorized
    /// @param transaction The transaction that was authorized
    /// @param transactionHash The hash of the transaction
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param memo Additional data or information about the payment
    /// @param itemId The item ID
    event Authorized(
        EscrowPayment.Transaction transaction, bytes32 transactionHash, bytes32 onBehalfOf, bytes memo, bytes32 itemId
    );

    /// @notice Emitted when a pull payment is completed
    /// @param targetAsset The target asset received by merchant
    /// @param receivedTargetAssetAmount The amount of target asset received by merchant
    /// @param swappedSourceAssetAmount The amount of source asset that was swapped and paid to merchant
    /// @param refundedSourceAssetAmount The amount of source asset refunded to user
    /// @param protocolFeeInSourceToken The amount of source asset paid for protocol as fee
    /// @param transactionHash The hash of the authorized transaction
    event PaymentSettled(
        address indexed targetAsset,
        uint248 receivedTargetAssetAmount,
        uint248 swappedSourceAssetAmount,
        uint248 refundedSourceAssetAmount,
        uint248 protocolFeeInSourceToken,
        bytes32 transactionHash
    );

    /// @notice Sets the treasury address
    /// @param treasury The new treasury address
    function setTreasury(address treasury) external;

    /// @notice Gets the treasury address
    /// @return treasury The treasury address
    function getTreasury() external view returns (address treasury);

    /// @notice Gets the SXT token address
    /// @return sxt The SXT token address
    function getSXT() external view returns (address sxt);

    /// @notice Sets the payment asset
    /// @param assetAddress The asset to set
    /// @param paymentAsset AssetManagement.PaymentAsset struct
    /// @param path The path for the source asset to swap to USDT (sourceAsset => USDT)
    function setPaymentAsset(
        address assetAddress,
        AssetManagement.PaymentAsset calldata paymentAsset,
        bytes calldata path
    ) external;

    /// @notice Removes an asset from the payment assets
    /// @param asset The asset to remove
    function removePaymentAsset(address asset) external;

    /// @notice Gets the payment asset
    /// @param asset The asset to get
    /// @return paymentAsset The payment asset
    function getPaymentAsset(address asset) external view returns (AssetManagement.PaymentAsset memory paymentAsset);

    /// @notice Allows for sending ERC20 tokens to a target address
    /// @param asset The address of the ERC20 token to send
    /// @param amount The amount of tokens to send
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param itemId The item ID
    function send(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external;

    /// @notice Allows for sending ERC20 tokens to a target address with a callback contract
    /// @param asset The address of the ERC20 token to send
    /// @param amount The amount of tokens to send
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param callbackContractAddress The address of the callback contract
    /// @param callbackData The data to send to the callback contract
    function sendWithCallback(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        address callbackContractAddress,
        bytes calldata callbackData
    ) external;

    /// @notice Authorizes a payment to a target address
    /// the payment will be pulled from `msg.sender` and held in ZKpay contract as escrow
    /// the payment is accounted for `onBehalfOf` which means that any refunded amount will be send to `onBehalfOf`
    /// @param asset The address of the ERC20 token to send
    /// @param amount The amount of tokens to send
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param itemId The item ID
    /// @return transactionHash The hash of the transaction
    function authorize(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external returns (bytes32 transactionHash);

    /// @notice Authorizes a payment to a target address with a callback contract
    /// the payment will be pulled from `msg.sender` and held in ZKpay contract as escrow
    /// the payment is accounted for `onBehalfOf` which means that any refunded amount will be send to `onBehalfOf`
    /// @param asset The address of the ERC20 token to send
    /// @param amount The amount of tokens to send
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param callbackContractAddress The address of the callback contract
    /// @param callbackData The data to send to the callback contract
    /// @return transactionHash The hash of the transaction
    function authorizeWithCallback(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        address callbackContractAddress,
        bytes calldata callbackData
    ) external returns (bytes32 transactionHash);

    /// @notice Sets the merchant configuration for the caller
    /// @param config Merchant configuration struct
    /// @param path The path for the target asset to swap to USDT (USDT => targetAsset)
    function setMerchantConfig(MerchantLogic.MerchantConfig calldata config, bytes calldata path) external;

    /// @notice Returns the merchant configuration for a given merchant
    /// @param merchant The merchant address
    /// @return config The merchant configuration
    function getMerchantConfig(address merchant) external view returns (MerchantLogic.MerchantConfig memory config);

    /// @notice Sets the price for an item
    /// @param item The item hash
    /// @param price The price in USD 18 decimals precision
    /// @dev msg.sender is the merchant address
    function setPaywallItemPrice(bytes32 item, uint248 price) external;

    /// @notice Gets the price for an item
    /// @param item The item hash
    /// @param merchant The merchant address
    /// @return price The price in USD 18 decimals precision
    function getPaywallItemPrice(bytes32 item, address merchant) external view returns (uint248 price);

    /// @notice Gets the executor address
    /// @return executor The executor address
    function getExecutorAddress() external view returns (address executor);

    /// @notice Settles an authorized payment by swapping source asset to target asset
    /// @param sourceAsset The source asset that was authorized
    /// @param sourceAssetAmount The amount of source asset that was authorized
    /// @param from The address that authorized the payment
    /// @param transactionHash The hash of the authorized transaction
    /// @param maxUsdValueOfTargetToken The maximum amount of target asset to settle to merchant
    function settlePayment(
        address sourceAsset,
        uint248 sourceAssetAmount,
        address from,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken
    ) external;
}
