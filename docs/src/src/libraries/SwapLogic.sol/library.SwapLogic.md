# SwapLogic
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/libraries/SwapLogic.sol)

Library for swapping assets


## State Variables
### WORD_SIZE

```solidity
uint256 internal constant WORD_SIZE = 0x20
```


### ADDRESS_SIZE

```solidity
uint256 internal constant ADDRESS_SIZE = 20
```


### FEE_SIZE

```solidity
uint256 internal constant FEE_SIZE = 3
```


### ADDRESS_PLUS_FEE

```solidity
uint256 internal constant ADDRESS_PLUS_FEE = 23
```


### ADDRESS_OFFSET_BITS

```solidity
uint256 internal constant ADDRESS_OFFSET_BITS = 96
```


### MIN_AMOUNT_OUT

```solidity
uint256 internal constant MIN_AMOUNT_OUT = 0
```


## Functions
### setConfig

set the essential config for swaps


```solidity
function setConfig(SwapLogicStorage storage _swapLogicStorage, SwapLogicConfig memory newConfig) internal;
```

### isValidPath

validate the path

valid path is either 20 bytes (single asset) or (20 + 3) * n bytes (multiple assets)
there should be N asset addresses + (N-1) path fees


```solidity
function isValidPath(bytes memory path) internal pure returns (bool valid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`path`|`bytes`|the swap path|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool`|true if the path is valid, false otherwise|


### calldataExtractPathDestinationAsset

extract the destination asset from the path


```solidity
function calldataExtractPathDestinationAsset(bytes calldata path) internal pure returns (address tokenOut);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`path`|`bytes`|the swap path|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenOut`|`address`|the destination asset|


### extractPathDestinationAsset

extract the destination asset from the path

this function assumes the path is valid and does not check for it. use isValidPath to check for validity


```solidity
function extractPathDestinationAsset(bytes memory path) internal pure returns (address tokenOut);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`path`|`bytes`|the swap path|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenOut`|`address`|the destination asset|


### extractPathOriginAsset

extract the origin asset from the path

this function assumes the path is valid and does not check for it. use isValidPath to check for validity


```solidity
function extractPathOriginAsset(bytes memory path) internal pure returns (address tokenIn);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`path`|`bytes`|the swap path|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenIn`|`address`|the source asset|


### calldataExtractPathOriginAsset

extract the origin asset from the path

this function assumes the path is valid and does not check for it. use isValidPath to check for validity


```solidity
function calldataExtractPathOriginAsset(bytes calldata path) internal pure returns (address tokenIn);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`path`|`bytes`|the swap path|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenIn`|`address`|the source asset|


### setSourceAssetPath

set the path for the source asset


```solidity
function setSourceAssetPath(SwapLogicStorage storage _swapLogicStorage, bytes calldata path) internal;
```

### setMerchantTargetAssetPath

set the path for the target asset


```solidity
function setMerchantTargetAssetPath(
    SwapLogicStorage storage _swapLogicStorage,
    address merchant,
    bytes calldata path
) internal;
```

### getMerchantPayoutAsset

get the payout asset address for a merchant by extracting it from their target asset path


```solidity
function getMerchantPayoutAsset(SwapLogicStorage storage _swapLogicStorage, address merchant)
    internal
    view
    returns (address payoutAsset);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_swapLogicStorage`|`SwapLogicStorage`|the storage of the swap logic|
|`merchant`|`address`|the address of the merchant|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`payoutAsset`|`address`|the address of the merchant's payout asset|


### _connect2Paths

connect two paths with optimization to remove redundant hops


```solidity
function _connect2Paths(bytes memory pathA, bytes memory pathB) internal pure returns (bytes memory result);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pathA`|`bytes`|the first path|
|`pathB`|`bytes`|the second path|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`result`|`bytes`|the optimized connected path|


### _swapExactAmountIn

does swap with uniswap v3 router using exact input amount

this function assumes the path is >= 1 hop valid path, make sure validate the path before calling this function

the contract that implements this library should hold `amountIn` of the source asset


```solidity
function _swapExactAmountIn(address router, bytes memory path, uint256 amountIn, address recipient)
    internal
    returns (uint256 amountOut);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`router`|`address`|the uniswap v3 router address|
|`path`|`bytes`|the path to swap|
|`amountIn`|`uint256`|the amount of the source asset to swap|
|`recipient`|`address`|the recipient of the destination asset|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountOut`|`uint256`|the amount of the destination asset received|


### swapExactSourceAssetAmount

Swaps source asset to merchant target asset using exact source amount, returns swap results without handling transfers


```solidity
function swapExactSourceAssetAmount(
    SwapLogicStorage storage _swapLogicStorage,
    address sourceAsset,
    address merchant,
    uint256 sourceAssetAmountIn,
    address targetAssetRecipient,
    bytes memory customSourceAssetPath
) internal returns (uint256 receivedTargetAssetAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_swapLogicStorage`|`SwapLogicStorage`|the storage of the swap logic|
|`sourceAsset`|`address`|the source asset to swap from|
|`merchant`|`address`|the merchant address to get target asset path|
|`sourceAssetAmountIn`|`uint256`||
|`targetAssetRecipient`|`address`|the recipient of the target asset|
|`customSourceAssetPath`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`receivedTargetAssetAmount`|`uint256`|the amount of received target asset tokens from the swapping router|


## Events
### SourceAssetPathSet
Emitted when a source asset path is set by admin


```solidity
event SourceAssetPathSet(address indexed asset, bytes path);
```

### MerchantTargetAssetPathSet
Emitted when a merchant target asset path is set by merchant


```solidity
event MerchantTargetAssetPathSet(address indexed merchant, bytes path);
```

## Errors
### InvalidPath
Error thrown when the provided swap path bytes are not a valid Uniswap V3 path encoding


```solidity
error InvalidPath();
```

### PathMustEndWithUSD
Error thrown when the swap path does not end with the USD token defined in the contract config


```solidity
error PathMustEndWithUSD();
```

### PathMustStartWithUSD
Error thrown when the swap path does not start with the USD token defined in the contract config


```solidity
error PathMustStartWithUSD();
```

### ZeroAddress
Error thrown when the provided address is the zero address


```solidity
error ZeroAddress();
```

### PathsDoNotConnect
Error thrown when the paths do not connect


```solidity
error PathsDoNotConnect();
```

## Structs
### SwapLogicConfig

```solidity
struct SwapLogicConfig {
    address router;
    address usd;
}
```

### AssetSwapPaths

```solidity
struct AssetSwapPaths {
    mapping(address asset => bytes sourceAssetPath) sourceAssetPaths;
    mapping(address merchant => bytes targetAssetPath) merchantTargetAssetPaths;
}
```

### SwapLogicStorage

```solidity
struct SwapLogicStorage {
    SwapLogicConfig swapLogicConfig;
    AssetSwapPaths assetSwapPaths;
}
```

