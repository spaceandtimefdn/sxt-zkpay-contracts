# PayWallLogic
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/libraries/PayWallLogic.sol)

Library for managing merchant paywall prices


## Functions
### setItemPrice

set the price for an item


```solidity
function setItemPrice(
    PayWallLogicStorage storage _paywallLogicStorage,
    address merchant,
    bytes32 item,
    uint248 price
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paywallLogicStorage`|`PayWallLogicStorage`|the storage of the paywall logic|
|`merchant`|`address`|the merchant address|
|`item`|`bytes32`|the item hash|
|`price`|`uint248`|the price|


### getItemPrice

get the price for an item


```solidity
function getItemPrice(PayWallLogicStorage storage _paywallLogicStorage, address merchant, bytes32 item)
    internal
    view
    returns (uint248);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paywallLogicStorage`|`PayWallLogicStorage`|the storage of the paywall logic|
|`merchant`|`address`|the merchant address|
|`item`|`bytes32`|the item hash|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint248`|the price|


## Events
### ItemPriceSet
Emitted when the price for an item is set


```solidity
event ItemPriceSet(address indexed merchant, bytes32 indexed item, uint248 price);
```

## Structs
### PayWallLogicStorage

```solidity
struct PayWallLogicStorage {
    mapping(address merchant => mapping(bytes32 item => uint248 price)) paywallPrices;
}
```

