# ISafeExecutor
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/interfaces/ISafeExecutor.sol)

Interface for the SafeExecutor contract


## Functions
### execute

Executes a call to the target contract


```solidity
function execute(address target, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`target`|`address`|The address of the target contract|
|`data`|`bytes`|The data to send to the target contract|


## Errors
### CallFailed
Thrown when a call to the target contract fails


```solidity
error CallFailed();
```

### InvalidTarget
Thrown when the target address has no contract code


```solidity
error InvalidTarget();
```

### Unauthorized
Thrown when caller is not authorized


```solidity
error Unauthorized();
```

