# MerchantLogic
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/libraries/MerchantLogic.sol)


## State Variables
### PERCENTAGE_PRECISION

```solidity
uint32 public constant PERCENTAGE_PRECISION = 1e6
```


### TOTAL_PERCENTAGE

```solidity
uint32 public constant TOTAL_PERCENTAGE = 100 * PERCENTAGE_PRECISION
```


### MAX_PAYOUT_RECIPIENTS

```solidity
uint256 public constant MAX_PAYOUT_RECIPIENTS = 16
```


### SEND_METHOD

```solidity
bytes1 public constant SEND_METHOD = bytes1(uint8(1 << 0))
```


### AUTHORIZE_METHOD

```solidity
bytes1 public constant AUTHORIZE_METHOD = bytes1(uint8(1 << 1))
```


## Functions
### setConfig


```solidity
function setConfig(
    MerchantLogicStorage storage merchantLogicStorage,
    address merchant,
    MerchantConfig memory config
) internal;
```

### getConfig


```solidity
function getConfig(MerchantLogicStorage storage merchantLogicStorage, address merchant)
    internal
    view
    returns (MerchantConfig memory config);
```

### setItemIdCallback


```solidity
function setItemIdCallback(
    MerchantLogicStorage storage merchantLogicStorage,
    address merchant,
    bytes32 itemId,
    ItemIdCallbackConfig memory callbackConfig
) internal;
```

### getItemIdCallback


```solidity
function getItemIdCallback(MerchantLogicStorage storage merchantLogicStorage, address merchant, bytes32 itemId)
    internal
    view
    returns (ItemIdCallbackConfig memory callbackConfig);
```

## Events
### MerchantConfigSet
Emitted when a merchant updates their configuration


```solidity
event MerchantConfigSet(
    address indexed merchant, address[] payoutAddresses, uint32[] payoutPercentages, bool allowUserCustomPath
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`merchant`|`address`|Address of the merchant|
|`payoutAddresses`|`address[]`|Array of payout addresses|
|`payoutPercentages`|`uint32[]`|Array of payout percentages|
|`allowUserCustomPath`|`bool`|Whether users can provide custom swap paths|

## Errors
### InvalidPayoutPercentageSum
Error thrown when payout percentages don't sum to 100%


```solidity
error InvalidPayoutPercentageSum();
```

### PayoutAddressCannotBeZero
Error thrown when payout address is zero


```solidity
error PayoutAddressCannotBeZero();
```

### NoPayoutRecipients
Error thrown when no payout recipients are provided


```solidity
error NoPayoutRecipients();
```

### PayoutArrayLengthMismatch
Error thrown when payout address and percentage arrays have different lengths


```solidity
error PayoutArrayLengthMismatch();
```

### ZeroPayoutPercentage
Error thrown when a payout percentage is zero


```solidity
error ZeroPayoutPercentage();
```

### TooManyPayoutRecipients
Error thrown when too many payout recipients are specified


```solidity
error TooManyPayoutRecipients();
```

### UnsupportedPaymentMethod

```solidity
error UnsupportedPaymentMethod();
```

### ItemIdCallbackNotConfigured
Error thrown when item ID callback is not configured


```solidity
error ItemIdCallbackNotConfigured();
```

### UserCustomPathNotAllowed
Error thrown when user provides custom path but merchant doesn't allow it


```solidity
error UserCustomPathNotAllowed();
```

## Structs
### MerchantConfig

```solidity
struct MerchantConfig {
    bool allowUserCustomPath;
    address[] payoutAddresses;
    uint32[] payoutPercentages;
}
```

### MerchantLogicStorage

```solidity
struct MerchantLogicStorage {
    mapping(address merchantAddress => MerchantLogic.MerchantConfig merchantConfig) merchantConfigs;
    mapping(bytes32 => MerchantLogic.ItemIdCallbackConfig) itemIdCallbackConfigs;
}
```

### ItemIdCallbackConfig

```solidity
struct ItemIdCallbackConfig {
    bytes4 funcSig;
    address contractAddress;
    bool includePaymentMetadata;
    bytes1 acceptedMethods;
}
```

