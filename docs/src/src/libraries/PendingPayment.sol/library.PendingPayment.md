# PendingPayment
[Git Source](https://github.com/spaceandtimefdn/sxt-zkpay-contracts/blob/e2e689dfecdfce7e638525fdf3f9afb9596fc268/src/libraries/PendingPayment.sol)


## Functions
### incrementNonce

Increments the global nonce for the pending payment


```solidity
modifier incrementNonce(PendingPaymentStorage storage pendingPaymentStorage) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pendingPaymentStorage`|`PendingPaymentStorage`|The storage of the pending payment|


### generateTransactionHash

Generates the transaction hash


```solidity
function generateTransactionHash(Transaction memory transaction, uint248 nonce) internal view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`transaction`|`Transaction`|The transaction to generate the hash for|
|`nonce`|`uint248`|Nonce of the transaction|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|transactionHash The hash of the transaction|


### authorize

Authorizes a transaction


```solidity
function authorize(PendingPaymentStorage storage pendingPaymentStorage, Transaction memory transaction)
    internal
    incrementNonce(pendingPaymentStorage)
    returns (bytes32 transactionHash);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pendingPaymentStorage`|`PendingPaymentStorage`|The storage of the pending payment|
|`transaction`|`Transaction`|The transaction to authorize|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`transactionHash`|`bytes32`|The hash of the transaction|


### completeAuthorizedTransaction

complete authorized transaction from the pending payment


```solidity
function completeAuthorizedTransaction(
    PendingPaymentStorage storage pendingPaymentStorage,
    Transaction memory transaction,
    bytes32 transactionHash
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pendingPaymentStorage`|`PendingPaymentStorage`|The storage of the pending payment|
|`transaction`|`Transaction`|The transaction to pull the payment from|
|`transactionHash`|`bytes32`|the authorized transaction hash|


## Errors
### TransactionNotAuthorized

```solidity
error TransactionNotAuthorized();
```

### TransactionHashMismatch

```solidity
error TransactionHashMismatch();
```

## Structs
### Transaction
Transaction struct

The transaction struct is not meant to be stored


```solidity
struct Transaction {
    /// @notice The asset being transferred
    address asset;
    /// @notice The amount of the source asset
    uint248 amount;
    /// @notice The address of the sender
    address from;
    /// @notice The address of the receiver
    address to;
}
```

### PendingPaymentStorage

```solidity
struct PendingPaymentStorage {
    /// @notice Global nonce for the pending payment
    uint248 nonce;
    /// @notice Mapping of transaction hashes to their nonces, if nonce is 0, the transaction is not authorized
    mapping(bytes32 transactionHash => uint248 transactionNonce) transactionNonces;
}
```

