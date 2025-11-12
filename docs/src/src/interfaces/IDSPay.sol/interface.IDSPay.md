# IDSPay
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/interfaces/IDSPay.sol)


## Functions
### setPaymentAsset

Sets the payment asset


```solidity
function setPaymentAsset(
    address assetAddress,
    AssetManagement.PaymentAsset calldata paymentAsset,
    bytes calldata path
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetAddress`|`address`|The asset to set|
|`paymentAsset`|`AssetManagement.PaymentAsset`|AssetManagement.PaymentAsset struct|
|`path`|`bytes`|The path for the source asset to swap to USD (sourceAsset => USD)|


### removePaymentAsset

Removes an asset from the payment assets


```solidity
function removePaymentAsset(address asset) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset to remove|


### getPaymentAsset

Gets the payment asset


```solidity
function getPaymentAsset(address asset) external view returns (AssetManagement.PaymentAsset memory paymentAsset);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`paymentAsset`|`AssetManagement.PaymentAsset`|The payment asset|


### send

Allows for sending ERC20 tokens to a target address


```solidity
function send(
    address asset,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The address of the ERC20 token to send|
|`amount`|`uint248`|The amount of tokens to send|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment is made|
|`merchant`|`address`|The merchant address|
|`memo`|`bytes`|Additional data or information about the payment|
|`itemId`|`bytes32`|The item ID|


### sendPathOverride

Allows for sending ERC20 tokens with a custom swap path override


```solidity
function sendPathOverride(
    bytes calldata customSourceAssetPath,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`customSourceAssetPath`|`bytes`|The custom swap path to override the stored sourceAssetPaths mapping|
|`amount`|`uint248`|The amount of tokens to send|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment is made|
|`merchant`|`address`|The merchant address|
|`memo`|`bytes`|Additional data or information about the payment|
|`itemId`|`bytes32`|The item ID|


### sendWithCallbackPathOverride

Allows for sending ERC20 tokens with a custom swap path override and a callback contract


```solidity
function sendWithCallbackPathOverride(
    bytes calldata customSourceAssetPath,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId,
    bytes calldata callbackData
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`customSourceAssetPath`|`bytes`|The custom swap path to override the stored sourceAssetPaths mapping|
|`amount`|`uint248`|The amount of tokens to send|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment is made|
|`merchant`|`address`|The merchant address|
|`memo`|`bytes`|Additional data or information about the payment|
|`itemId`|`bytes32`|The item ID, this is used to identify the callback contract|
|`callbackData`|`bytes`|The data to send to the callback contract|


### sendWithCallback

Allows for sending ERC20 tokens to a target address with a callback contract


```solidity
function sendWithCallback(
    address asset,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId,
    bytes calldata callbackData
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The address of the ERC20 token to send|
|`amount`|`uint248`|The amount of tokens to send|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment is made|
|`merchant`|`address`|The merchant address|
|`memo`|`bytes`|Additional data or information about the payment|
|`itemId`|`bytes32`|The item ID, this is used to identify the callback contract|
|`callbackData`|`bytes`|The data to send to the callback contract|


### authorize

Authorizes a payment to a target merchant
the payment will be pulled from `msg.sender` and held pending in DSpay contract
the payment is accounted for `onBehalfOf` but any refunded amount will be send to `msg.sender`


```solidity
function authorize(
    address asset,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The address of the ERC20 token to send|
|`amount`|`uint248`|The amount of tokens to send|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment is made|
|`merchant`|`address`|The merchant address|
|`memo`|`bytes`|Additional data or information about the payment|
|`itemId`|`bytes32`|The item ID|


### authorizeWithCallback

Authorizes a payment to a target merchant with a callback contract
the payment will be pulled from `msg.sender` and held pending in DSpay contract
the payment is accounted for `onBehalfOf` but any refunded amount will be send to `msg.sender`


```solidity
function authorizeWithCallback(
    address asset,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId,
    bytes calldata callbackData
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The address of the ERC20 token to send|
|`amount`|`uint248`|The amount of tokens to send|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment is made|
|`merchant`|`address`|The merchant address|
|`memo`|`bytes`|Additional data or information about the payment|
|`itemId`|`bytes32`|The item ID, used to identify the callback contract|
|`callbackData`|`bytes`|The data to send to the callback contract|


### setMerchantConfig

Sets the merchant configuration for the caller


```solidity
function setMerchantConfig(MerchantLogic.MerchantConfig calldata config, bytes calldata path) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`config`|`MerchantLogic.MerchantConfig`|Merchant configuration struct|
|`path`|`bytes`|The path for the target asset to swap to USD (USD => targetAsset)|


### getMerchantConfig

Returns the merchant configuration for a given merchant


```solidity
function getMerchantConfig(address merchant) external view returns (MerchantLogic.MerchantConfig memory config);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`merchant`|`address`|The merchant address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`config`|`MerchantLogic.MerchantConfig`|The merchant configuration|


### setPaywallItemPrice

Sets the price for an item

msg.sender is the merchant address


```solidity
function setPaywallItemPrice(bytes32 item, uint248 price) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`item`|`bytes32`|The item hash|
|`price`|`uint248`|The price in USD 18 decimals precision|


### getPaywallItemPrice

Gets the price for an item


```solidity
function getPaywallItemPrice(bytes32 item, address merchant) external view returns (uint248 price);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`item`|`bytes32`|The item hash|
|`merchant`|`address`|The merchant address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint248`|The price in USD 18 decimals precision|


### getExecutorAddress

Gets the executor address


```solidity
function getExecutorAddress() external view returns (address executor);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`executor`|`address`|The executor address|


### getSequencerConfig

Gets the sequencer configuration


```solidity
function getSequencerConfig()
    external
    view
    returns (AssetManagement.AssetManagementSequencerConfig memory sequencerConfig);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sequencerConfig`|`AssetManagement.AssetManagementSequencerConfig`|The current sequencer configuration|


### settleAuthorizedPayment

Settles an authorized payment


```solidity
function settleAuthorizedPayment(
    address sourceAsset,
    uint248 sourceAssetAmount,
    address from,
    bytes32 transactionHash,
    uint248 maxUsdValueOfTargetToken
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sourceAsset`|`address`|The source asset of the payment|
|`sourceAssetAmount`|`uint248`|The amount of source asset that was authorized|
|`from`|`address`|The address that made the original payment|
|`transactionHash`|`bytes32`|The hash of the transaction to settle|
|`maxUsdValueOfTargetToken`|`uint248`|Maximum USD value allowed for the target token|


### settleAuthorizedPaymentPathOverride

Settles an authorized payment


```solidity
function settleAuthorizedPaymentPathOverride(
    bytes calldata customSourceAssetPath,
    uint248 sourceAssetAmount,
    address from,
    bytes32 transactionHash,
    uint248 maxUsdValueOfTargetToken
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`customSourceAssetPath`|`bytes`|The custom swap path to override the stored sourceAssetPaths mapping|
|`sourceAssetAmount`|`uint248`|The amount of source asset that was authorized|
|`from`|`address`|The address that made the original payment|
|`transactionHash`|`bytes32`|The hash of the transaction to settle|
|`maxUsdValueOfTargetToken`|`uint248`|Maximum USD value allowed for the target token|


### setItemIdCallbackConfig

Sets callback configuration for an item ID


```solidity
function setItemIdCallbackConfig(bytes32 itemId, MerchantLogic.ItemIdCallbackConfig calldata config) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`itemId`|`bytes32`|The item ID|
|`config`|`MerchantLogic.ItemIdCallbackConfig`|The callback configuration|


### getItemIdCallbackConfig

Gets callback configuration for an item ID


```solidity
function getItemIdCallbackConfig(address merchant, bytes32 itemId)
    external
    view
    returns (MerchantLogic.ItemIdCallbackConfig memory config);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`merchant`|`address`|The merchant address|
|`itemId`|`bytes32`|The item ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`config`|`MerchantLogic.ItemIdCallbackConfig`|The callback configuration|


## Events
### SendPayment
Emitted when a payment is made


```solidity
event SendPayment(
    address indexed asset,
    uint248 amount,
    bytes32 onBehalfOf,
    address indexed merchant,
    bytes memo,
    uint248 amountInUSD,
    address indexed sender,
    bytes32 itemId
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset used for payment|
|`amount`|`uint248`|The amount of tokens used for payment|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment was made|
|`merchant`|`address`|The merchant address|
|`memo`|`bytes`|Additional data or information about the payment|
|`amountInUSD`|`uint248`|The amount in USD|
|`sender`|`address`|The address that initiated the payment|
|`itemId`|`bytes32`|The item ID|

### Authorized
Emitted when a payment is authorized


```solidity
event Authorized(
    PendingPayment.Transaction transaction, bytes32 transactionHash, bytes32 onBehalfOf, bytes memo, bytes32 itemId
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`transaction`|`PendingPayment.Transaction`|The transaction that was authorized|
|`transactionHash`|`bytes32`|The hash of the transaction|
|`onBehalfOf`|`bytes32`|The identifier on whose behalf the payment is made|
|`memo`|`bytes`|Additional data or information about the payment|
|`itemId`|`bytes32`|The item ID|

### AuthorizedPaymentSettled
Emitted when an authorized payment is settled


```solidity
event AuthorizedPaymentSettled(
    address indexed sourceAsset,
    uint248 sourceAssetAmount,
    address indexed payoutToken,
    uint256 receivedTargetAssetAmount,
    uint248 receivedRefundAmount,
    address indexed from,
    address merchant,
    bytes32 transactionHash
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sourceAsset`|`address`|The source asset of the payment|
|`sourceAssetAmount`|`uint248`|The amount of source asset that was authorized|
|`payoutToken`|`address`|The token the merchant received|
|`receivedTargetAssetAmount`|`uint256`|The amount received by the merchant in payout token|
|`receivedRefundAmount`|`uint248`|The amount refunded to the client|
|`from`|`address`|The address that made the original payment|
|`merchant`|`address`|The merchant address|
|`transactionHash`|`bytes32`|The transaction hash of the authorized payment|

