# AssetManagement
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/libraries/AssetManagement.sol)

Library for managing payment assets,

It allows for setting, removing and getting payment assets.


## Functions
### _checkSequencerUptime

Checks L2 sequencer uptime before allowing price feed operations


```solidity
function _checkSequencerUptime(AssetManagementSequencerConfig storage sequencerConfig) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sequencerConfig`|`AssetManagementSequencerConfig`|asset management sequencer configuration|


### _validatePriceFeed

Validates the price feed


```solidity
function _validatePriceFeed(PaymentAsset memory paymentAsset) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paymentAsset`|`PaymentAsset`|payment asset|


### set

Sets the payment asset


```solidity
function set(
    mapping(address asset => PaymentAsset) storage _assets,
    address asset,
    PaymentAsset memory paymentAsset
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`|assets mapping|
|`asset`|`address`|token address|
|`paymentAsset`|`PaymentAsset`|payment asset to set|


### remove

Disables an asset for new payments while preserving configuration for existing authorized payments


```solidity
function remove(mapping(address asset => PaymentAsset) storage _assets, address asset) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`|assets mapping|
|`asset`|`address`|token address|


### get

Gets the payment asset


```solidity
function get(mapping(address asset => PaymentAsset) storage _assets, address assetAddress)
    internal
    view
    returns (PaymentAsset storage asset);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`|assets mapping|
|`assetAddress`|`address`|token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`PaymentAsset`|asset|


### isSupported

Checks if an asset is supported for new payments


```solidity
function isSupported(mapping(address asset => PaymentAsset) storage _assets, address assetAddress)
    internal
    view
    returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`|assets mapping|
|`assetAddress`|`address`|token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the asset exists and is active, false otherwise|


### exists

Checks if an asset exists in the mapping (regardless of active status)


```solidity
function exists(mapping(address asset => PaymentAsset) storage _assets, address assetAddress)
    internal
    view
    returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`|assets mapping|
|`assetAddress`|`address`|token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the asset exists, false otherwise|


### _getPrice

Gets the price of an asset


```solidity
function _getPrice(
    mapping(address asset => PaymentAsset) storage _assets,
    AssetManagementSequencerConfig storage sequencerConfig,
    address assetAddress
) internal view returns (uint256 safePrice, uint8 priceFeedDecimals);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`|assets mapping|
|`sequencerConfig`|`AssetManagementSequencerConfig`|asset management sequencer configuration|
|`assetAddress`|`address`|token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`safePrice`|`uint256`|price of the asset|
|`priceFeedDecimals`|`uint8`|price feed decimals|


### convertToUsd

Internal helper function to convert a token amount to its equivalent USD value.

This function could revert if `tokenAmount * safePrice` overflows uint248


```solidity
function convertToUsd(
    mapping(address asset => PaymentAsset) storage _assets,
    AssetManagementSequencerConfig storage sequencerConfig,
    address assetAddress,
    uint248 tokenAmount
) internal view returns (uint248 usdValue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`|assets mapping|
|`sequencerConfig`|`AssetManagementSequencerConfig`|asset management sequencer configuration|
|`assetAddress`|`address`|The address of the asset to convert.|
|`tokenAmount`|`uint248`|The amount of the token (in its smallest unit, e.g., wei for ETH).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`usdValue`|`uint248`|The equivalent USD value in 18 decimal places.|


### convertUsdToToken

Internal helper function to convert a USD value to its equivalent token amount.


```solidity
function convertUsdToToken(
    mapping(address asset => PaymentAsset) storage _assets,
    AssetManagementSequencerConfig storage sequencerConfig,
    address asset,
    uint248 usdValue
) internal view returns (uint248 tokenAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`mapping(address asset => PaymentAsset)`||
|`sequencerConfig`|`AssetManagementSequencerConfig`|asset management sequencer configuration|
|`asset`|`address`|The address of the asset to convert.|
|`usdValue`|`uint248`|The USD value to convert in 18 decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenAmount`|`uint248`|The equivalent token amount.|


### transferAsset

Transfers asset to recipient and returns actual amount received


```solidity
function transferAsset(address asset, uint248 amount, address recipient) internal returns (uint248 amountReceived);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The address of the asset to transfer|
|`amount`|`uint248`|The amount to transfer|
|`recipient`|`address`|The recipient of the transfer|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountReceived`|`uint248`|The amount actually received by recipient|


### transferAssetFromCaller

Transfers asset from `from` to `recipient` and returns actual amount received


```solidity
function transferAssetFromCaller(address asset, uint248 amount, address recipient)
    internal
    returns (uint248 amountReceived);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The address of the asset to transfer|
|`amount`|`uint248`|The amount to transfer|
|`recipient`|`address`|The recipient of the transfer|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountReceived`|`uint248`|The amount actually received by recipient|


## Events
### AssetAdded
Emitted when a new asset is added


```solidity
event AssetAdded(
    address indexed asset, address priceFeed, uint8 tokenDecimals, uint64 stalePriceThresholdInSeconds
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset address|
|`priceFeed`|`address`|The price feed address|
|`tokenDecimals`|`uint8`|The token decimals|
|`stalePriceThresholdInSeconds`|`uint64`|The stale price threshold in seconds|

### AssetRemoved
Emitted when an asset is removed


```solidity
event AssetRemoved(address asset);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset address|

## Errors
### InvalidPriceFeed
Error thrown when the price feed is invalid


```solidity
error InvalidPriceFeed();
```

### AssetNotFound
Error thrown when the asset is not found


```solidity
error AssetNotFound();
```

### InvalidPriceFeedData
Error thrown when the price feed data is invalid


```solidity
error InvalidPriceFeedData();
```

### StalePriceFeedData
Error thrown when the price feed data is stale


```solidity
error StalePriceFeedData();
```

### AssetIsNotSupportedForThisMethod
Error thrown when the asset is not supported for this method


```solidity
error AssetIsNotSupportedForThisMethod();
```

### SequencerDown
Error thrown when the L2 sequencer is down


```solidity
error SequencerDown();
```

### GracePeriodNotOver
Error thrown when the sequencer uptime feed grace period has not passed


```solidity
error GracePeriodNotOver();
```

## Structs
### PaymentAsset
Defines payment asset configuration within the DSpay protocol.


```solidity
struct PaymentAsset {
    /// @notice  Price oracle
    address priceFeed;
    /// @notice  token decimals, added here in case erc20 token isn't fully compliant and doesn't expose that method.
    uint8 tokenDecimals;
    /// @notice threshold for price feed data in seconds
    uint64 stalePriceThresholdInSeconds;
    /// @notice whether the asset is active for new payments
    bool active;
}
```

### AssetManagementSequencerConfig
Global configuration for asset management sequencer


```solidity
struct AssetManagementSequencerConfig {
    /// @notice Chainlink L2 sequencer uptime feed address
    address sequencerUptimeFeed;
    /// @notice Grace period in seconds after sequencer is back up
    uint256 gracePeriod;
}
```

