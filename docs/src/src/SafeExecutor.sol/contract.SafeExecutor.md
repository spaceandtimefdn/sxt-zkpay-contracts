# SafeExecutor
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/SafeExecutor.sol)

**Inherits:**
[ISafeExecutor](/data/sxt-zkpay-contracts/docs/src/src/interfaces/ISafeExecutor.sol/interface.ISafeExecutor.md)

A contract that executes calls to other contracts
NOTE: this contract should not hold any funds, it's only used to execute calls to other contracts


## State Variables
### OWNER

```solidity
address public immutable OWNER
```


## Functions
### constructor


```solidity
constructor() ;
```

### onlyOwner


```solidity
modifier onlyOwner() ;
```

### execute

Executes a call to the target contract


```solidity
function execute(address target, bytes calldata data) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`target`|`address`|The address of the target contract|
|`data`|`bytes`|The data to send to the target contract|


