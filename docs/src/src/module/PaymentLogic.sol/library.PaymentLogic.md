# PaymentLogic
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/module/PaymentLogic.sol)

Library for processing payments, authorizations, and settlements in the DSPay protocol

Orchestrates interactions between asset management, swap logic, paywall, and payment systems


## Functions
### _validateAsset

Modifier to validate that an asset is supported for payment operations


```solidity
modifier _validateAsset(mapping(address asset => AssetManagement.PaymentAsset) storage _assets, address asset) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => AssetManagement.PaymentAsset)`|The assets mapping|
|`asset`|`address`|The asset address to validate|


### _validateMerchant

Modifier to validate that a merchant is properly configured


```solidity
modifier _validateMerchant(SwapLogic.SwapLogicStorage storage _swapLogicStorage, address merchant) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_swapLogicStorage`|`SwapLogic.SwapLogicStorage`|The swap logic storage|
|`merchant`|`address`|The merchant address to validate|


### _validateItemPrice

Validates that the payment amount meets the minimum item price requirement


```solidity
function _validateItemPrice(
    PayWallLogic.PayWallLogicStorage storage _paywallLogicStorage,
    address merchant,
    bytes32 itemId,
    uint248 amountInUSD
) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paywallLogicStorage`|`PayWallLogic.PayWallLogicStorage`|The paywall logic storage|
|`merchant`|`address`|The merchant address|
|`itemId`|`bytes32`|The item identifier|
|`amountInUSD`|`uint248`|The payment amount in USD|


### processPayment

Processes a direct payment with asset swapping to merchant's preferred payout token


```solidity
function processPayment(DSPay.DSPayStorage storage _dsPayStorage, ProcessPaymentParams memory params)
    internal
    _validateAsset(_dsPayStorage.assets, params.asset)
    _validateMerchant(_dsPayStorage.swapLogicStorage, params.merchant)
    returns (ProcessPaymentResult memory result);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dsPayStorage`|`DSPay.DSPayStorage`|The DSPay storage|
|`params`|`ProcessPaymentParams`|The payment parameters struct|


### authorizePayment

Authorizes a payment by transferring assets to a pending payment status


```solidity
function authorizePayment(DSPay.DSPayStorage storage _dsPayStorage, AuthorizePaymentParams memory params)
    internal
    _validateAsset(_dsPayStorage.assets, params.asset)
    _validateMerchant(_dsPayStorage.swapLogicStorage, params.merchant)
    returns (PendingPayment.Transaction memory transaction, bytes32 transactionHash, uint248 amountInUSD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dsPayStorage`|`DSPay.DSPayStorage`|The DSPay storage|
|`params`|`AuthorizePaymentParams`|The payment parameters struct|


### _computeSettlementBreakdown

Computes the breakdown of amounts for settlement (payment, refund)


```solidity
function _computeSettlementBreakdown(
    mapping(address asset => AssetManagement.PaymentAsset) storage _assets,
    AssetManagement.AssetManagementSequencerConfig storage sequencerConfig,
    address sourceAsset,
    uint248 sourceAssetAmount,
    uint248 maxUsdValueOfTargetToken
) internal view returns (uint248 toBePaidInSourceToken, uint248 toBeRefundedInSourceToken);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => AssetManagement.PaymentAsset)`|The assets mapping|
|`sequencerConfig`|`AssetManagement.AssetManagementSequencerConfig`|The sequencer configuration for L2 uptime checks|
|`sourceAsset`|`address`|The source asset address|
|`sourceAssetAmount`|`uint248`|The total source asset amount|
|`maxUsdValueOfTargetToken`|`uint248`|Maximum USD value allowed for the target token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`toBePaidInSourceToken`|`uint248`|Amount to be paid to merchant in source token|
|`toBeRefundedInSourceToken`|`uint248`|Amount to be refunded to client in source token|


### processSettlement

Settles a pending payment by
- completing the authorized transaction
- computing the settlement breakdown
- paying the merchant
- refunding the client


```solidity
function processSettlement(DSPay.DSPayStorage storage _dsPayStorage, ProcessSettlementParams memory params)
    internal
    returns (ProcessSettlementResult memory result);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dsPayStorage`|`DSPay.DSPayStorage`|The DSPay storage|
|`params`|`ProcessSettlementParams`|The settlement parameters struct|


### _distributePayouts

Distributes payout amount among multiple recipients according to their percentages


```solidity
function _distributePayouts(
    address[] memory addresses,
    uint32[] memory percentages,
    uint256 totalAmount,
    address payoutToken
) internal returns (uint256 totalReceivedPayoutAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`addresses`|`address[]`|Array of payout addresses|
|`percentages`|`uint32[]`|Array of payout percentages corresponding to addresses|
|`totalAmount`|`uint256`|Total amount to distribute|
|`payoutToken`|`address`|The token being distributed|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalReceivedPayoutAmount`|`uint256`|Total amount actually transferred to all recipients|


## Errors
### InsufficientPayment

```solidity
error InsufficientPayment();
```

### ZeroAmountReceived

```solidity
error ZeroAmountReceived();
```

### MerchantNotConfigured

```solidity
error MerchantNotConfigured();
```

## Structs
### ProcessPaymentParams
Parameters for processing a payment


```solidity
struct ProcessPaymentParams {
    address asset;
    uint248 amount;
    address merchant;
    bytes32 itemId;
    bytes customSourceAssetPath;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The source asset being processed|
|`amount`|`uint248`|Source asset amount being processed|
|`merchant`|`address`|The merchant address|
|`itemId`|`bytes32`|The item identifier|
|`customSourceAssetPath`|`bytes`||

### ProcessPaymentResult

```solidity
struct ProcessPaymentResult {
    address payoutToken;
    uint248 amountInUSD;
    uint256 receivedPayoutAmount;
}
```

### AuthorizePaymentParams

```solidity
struct AuthorizePaymentParams {
    address asset;
    uint248 amount;
    address merchant;
    bytes32 itemId;
}
```

### ProcessSettlementParams

```solidity
struct ProcessSettlementParams {
    bytes customSourceAssetPath;
    address sourceAsset;
    uint248 sourceAssetAmount;
    address from;
    address merchant;
    bytes32 transactionHash;
    uint248 maxUsdValueOfTargetToken;
}
```

### ProcessSettlementResult

```solidity
struct ProcessSettlementResult {
    address payoutToken;
    uint256 receivedTargetAssetAmount;
    uint248 receivedRefundAmount;
}
```

