// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PendingPayment
library PendingPayment {
    error TransactionNotAuthorized();
    error TransactionHashMismatch();

    /// @notice Transaction struct
    /// @dev The transaction struct is not meant to be stored

    // solhint-disable-next-line gas-struct-packing
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

    struct PendingPaymentStorage {
        /// @notice Global nonce for the pending payment
        uint248 nonce;
        /// @notice Mapping of transaction hashes to their nonces, if nonce is 0, the transaction is not authorized
        mapping(bytes32 transactionHash => uint248 transactionNonce) transactionNonces;
    }

    /// @notice Increments the global nonce for the pending payment
    /// @param pendingPaymentStorage The storage of the pending payment
    modifier incrementNonce(PendingPaymentStorage storage pendingPaymentStorage) {
        ++pendingPaymentStorage.nonce;
        _;
    }

    /// @notice Generates the transaction hash
    /// @param nonce Nonce of the transaction
    /// @param transaction The transaction to generate the hash for
    /// @return transactionHash The hash of the transaction
    function generateTransactionHash(Transaction memory transaction, uint248 nonce) internal view returns (bytes32) {
        return keccak256(abi.encode(transaction, nonce, block.chainid));
    }

    /// @notice Authorizes a transaction
    /// @param pendingPaymentStorage The storage of the pending payment
    /// @param transaction The transaction to authorize
    /// @return transactionHash The hash of the transaction
    function authorize(PendingPaymentStorage storage pendingPaymentStorage, Transaction memory transaction)
        internal
        incrementNonce(pendingPaymentStorage)
        returns (bytes32 transactionHash)
    {
        transactionHash = generateTransactionHash(transaction, pendingPaymentStorage.nonce);
        pendingPaymentStorage.transactionNonces[transactionHash] = pendingPaymentStorage.nonce;
    }

    /// @notice complete authorized transaction from the pending payment
    /// @param pendingPaymentStorage The storage of the pending payment
    /// @param transaction The transaction to pull the payment from
    /// @param transactionHash the authorized transaction hash
    function completeAuthorizedTransaction(
        PendingPaymentStorage storage pendingPaymentStorage,
        Transaction memory transaction,
        bytes32 transactionHash
    ) internal {
        uint248 transactionNonce = pendingPaymentStorage.transactionNonces[transactionHash];
        if (transactionNonce == 0) revert TransactionNotAuthorized();

        bytes32 expectedTransactionHash = generateTransactionHash(transaction, transactionNonce);

        if (transactionHash != expectedTransactionHash) {
            revert TransactionHashMismatch();
        }

        pendingPaymentStorage.transactionNonces[transactionHash] = 0;
    }
}
