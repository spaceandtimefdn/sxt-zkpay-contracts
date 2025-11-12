# DSPay
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/DSPay.sol)

**Inherits:**
[IDSPay](/data/sxt-zkpay-contracts/docs/src/src/interfaces/IDSPay.sol/interface.IDSPay.md), AccessControlDefaultAdminRules, ReentrancyGuard


## State Variables
### _dsPayStorage

```solidity
DSPayStorage internal _dsPayStorage
```


## Functions
### constructor


```solidity
constructor(
    address admin,
    SwapLogic.SwapLogicConfig memory swapLogicConfig,
    AssetManagement.AssetManagementSequencerConfig memory sequencerConfig
) AccessControlDefaultAdminRules(0, admin);
```

### _deployExecutor


```solidity
function _deployExecutor() internal;
```

### getExecutorAddress

Gets the executor address


```solidity
function getExecutorAddress() external view returns (address executor);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`executor`|`address`|The executor address|


### setPaymentAsset

Sets the payment asset


```solidity
function setPaymentAsset(
    address assetAddress,
    AssetManagement.PaymentAsset calldata paymentAsset,
    bytes calldata path
) external onlyRole(DEFAULT_ADMIN_ROLE);
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
function removePaymentAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE);
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


### _sendPayment


```solidity
function _sendPayment(
    address asset,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId,
    bytes memory customSourceAssetPath
) internal returns (PaymentLogic.ProcessPaymentResult memory result);
```

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
) external nonReentrant;
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
) external nonReentrant;
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


### _sendWithCallback


```solidity
function _sendWithCallback(SendWithCallbackParams memory params, bytes calldata memo) internal;
```

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
) external nonReentrant;
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
) external nonReentrant;
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


### _authorize


```solidity
function _authorize(
    address asset,
    uint248 amount,
    bytes32 onBehalfOf,
    address merchant,
    bytes calldata memo,
    bytes32 itemId
) internal returns (PaymentMetadata memory metadata);
```

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
) external nonReentrant;
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
) external nonReentrant;
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


### _settleAuthorizedPayment


```solidity
function _settleAuthorizedPayment(
    bytes memory customSourceAssetPath,
    address sourceAsset,
    uint248 sourceAssetAmount,
    address from,
    address merchant,
    bytes32 transactionHash,
    uint248 maxUsdValueOfTargetToken
) internal;
```

### settleAuthorizedPayment

Settles an authorized payment


```solidity
function settleAuthorizedPayment(
    address sourceAsset,
    uint248 sourceAssetAmount,
    address from,
    bytes32 transactionHash,
    uint248 maxUsdValueOfTargetToken
) external nonReentrant;
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
) external nonReentrant;
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


```solidity
function setItemIdCallbackConfig(bytes32 itemId, MerchantLogic.ItemIdCallbackConfig calldata config) external;
```

### getItemIdCallbackConfig


```solidity
function getItemIdCallbackConfig(address merchant, bytes32 itemId)
    external
    view
    returns (MerchantLogic.ItemIdCallbackConfig memory config);
```

## Errors
### InvalidMerchant

```solidity
error InvalidMerchant();
```

### MerchantAddressCannotBeZero
Error thrown when the merchant address is zero


```solidity
error MerchantAddressCannotBeZero();
```

## Structs
### PaymentMetadata

```solidity
struct PaymentMetadata {
    address payoutToken;
    uint256 payoutAmount;
    uint248 amountInUSD;
    bytes32 onBehalfOf;
    address sender;
    bytes32 itemId;
    address merchant;
    PaymentMethod method;
}
```

### SendWithCallbackParams

```solidity
struct SendWithCallbackParams {
    address asset;
    uint248 amount;
    bytes32 onBehalfOf;
    address merchant;
    bytes32 itemId;
    bytes callbackData;
    bytes customSourceAssetPath;
}
```

### DSPayStorage

```solidity
struct DSPayStorage {
    address executorAddress;
    mapping(address asset => AssetManagement.PaymentAsset) assets;
    AssetManagement.AssetManagementSequencerConfig assetManagementSequencerConfig;
    MerchantLogic.MerchantLogicStorage merchantLogicStorage;
    SwapLogic.SwapLogicStorage swapLogicStorage;
    PayWallLogic.PayWallLogicStorage paywallLogicStorage;
    PendingPayment.PendingPaymentStorage pendingPaymentStorage;
}
```

## Enums
### PaymentMethod
Enum representing the payment method that triggered a callback


```solidity
enum PaymentMethod {
    SEND,
    AUTHORIZE
}
```

