// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "../libraries/AssetManagement.sol";
import {QueryLogic} from "../libraries/QueryLogic.sol";
import {MerchantLogic} from "../libraries/MerchantLogic.sol";

interface IZKPay {
    /// @notice Emitted when the treasury address is set
    /// @param treasury The new treasury address
    event TreasurySet(address indexed treasury);

    /// @notice Emitted when a new query payment is submitted
    /// @param queryHash The unique hash representing the query
    /// @param asset The asset used for the payment
    /// @param amount The amount of tokens used for the payment
    /// @param source The source address of the payment
    /// @param amountInUSD The amount in USD
    event NewQueryPayment(
        bytes32 indexed queryHash, address indexed asset, uint248 amount, address indexed source, uint248 amountInUSD
    );

    /// @notice Emitted when a callback fails.
    /// @param queryHash The hash of the query that failed.
    /// @param callbackClientContractAddress The address of the callback client contract.
    event CallbackFailed(bytes32 indexed queryHash, address indexed callbackClientContractAddress);

    /// @notice Emitted when a callback succeeds.
    /// @param queryHash The hash of the query that succeeded.
    /// @param callbackClientContractAddress The address of the callback client contract.
    event CallbackSucceeded(bytes32 indexed queryHash, address indexed callbackClientContractAddress);

    /// @notice Emitted when a query payment is settled.
    /// @param queryHash The hash of the query that was settled.
    /// @param paidAmount The amount of payment used for fulfilling the query.
    /// @param refundAmount The amount of payment remaining after fulfilling the query.
    /// @param merchantPayoutAmount The amount of payment paid to the merchant.
    /// @param protocolFeeAmount The amount of protocol fee in source token.
    event PaymentSettled(
        bytes32 indexed queryHash,
        uint248 paidAmount,
        uint248 refundAmount,
        uint248 merchantPayoutAmount,
        uint248 protocolFeeAmount
    );

    /// @notice Emitted when a query is fulfilled.
    /// @param queryHash The hash of the query that was fulfilled.
    event QueryFulfilled(bytes32 indexed queryHash);

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

    /// @notice Cancel a query if it has expired.
    /// @param queryHash The hash of the query to be canceled.
    /// @param queryRequest The struct containing the query details.
    function cancelExpiredQuery(bytes32 queryHash, QueryLogic.QueryRequest calldata queryRequest) external;

    /// @notice Submit a query with a payment in ERC20 tokens.
    /// @param asset The ERC20 token used for the payment.
    /// @param amount The amount of tokens to deposit.
    /// @param queryRequest The struct containing the query details.
    /// @return queryHash The unique hash representing the query.
    function query(address asset, uint248 amount, QueryLogic.QueryRequest calldata queryRequest)
        external
        returns (bytes32 queryHash);

    /// @notice Validates a query request by checking query nonce and query hash are valid against the query request.
    /// @param queryHash The unique hash representing the query.
    /// @param queryRequest The struct containing the query details.
    function validateQueryRequest(bytes32 queryHash, QueryLogic.QueryRequest calldata queryRequest) external view;

    /// @notice Sends the results of a query back to the callback contract.
    /// @param queryHash The unique identifier for the submitted query.
    /// @param queryRequest The struct containing the query details.
    /// @param queryResult The result of the query.
    /// @return gasUsed The amount of gas used to fulfill the query.
    function fulfillQuery(bytes32 queryHash, QueryLogic.QueryRequest calldata queryRequest, bytes calldata queryResult)
        external
        returns (uint248 gasUsed);

    /// @notice Allows for sending ERC20 tokens to a target address
    /// @param asset The address of the ERC20 token to send
    /// @param amount The amount of tokens to send
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param target The target address to receive the payment
    /// @param memo Additional data or information about the payment
    /// @param itemId The item ID
    function send(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address target,
        bytes calldata memo,
        bytes32 itemId
    ) external;

    /// @notice Authorizes a payment to a target address
    /// the payment will be pulled from `msg.sender` and held in ZKpay contract as escrow
    /// the payment is accounted for `onBehalfOf` which means that any refunded amount will be send to `onBehalfOf`
    /// @param asset The address of the ERC20 token to send
    /// @param amount The amount of tokens to send
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param itemId The item ID
    function authorize(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external;

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
}
