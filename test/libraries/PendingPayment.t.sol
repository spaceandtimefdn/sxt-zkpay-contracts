// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PendingPayment} from "../../src/libraries/PendingPayment.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";

contract PendingPaymentWrapper {
    PendingPayment.PendingPaymentStorage internal _pendingPaymentStorage;

    function authorize(PendingPayment.Transaction calldata transaction) external {
        PendingPayment.authorize(_pendingPaymentStorage, transaction);
    }

    function getNonce() external view returns (uint248) {
        return _pendingPaymentStorage.nonce;
    }

    function getTransactionNonce(bytes32 transactionHash) external view returns (uint248) {
        return _pendingPaymentStorage.transactionNonces[transactionHash];
    }

    function generateTransactionHash(PendingPayment.Transaction calldata transaction, uint248 nonce)
        external
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(transaction, nonce, block.chainid));
    }

    function setNonce(uint248 nonce) external {
        _pendingPaymentStorage.nonce = nonce;
    }

    function completeAuthorizedTransaction(PendingPayment.Transaction calldata transaction, bytes32 transactionHash)
        external
    {
        PendingPayment.completeAuthorizedTransaction(_pendingPaymentStorage, transaction, transactionHash);
    }
}

contract PendingPaymentTest is Test {
    PendingPaymentWrapper internal _wrapper;
    PendingPayment.Transaction internal _sampleTransaction;

    function setUp() public {
        _wrapper = new PendingPaymentWrapper();

        _sampleTransaction = PendingPayment.Transaction({
            asset: address(0x1234),
            amount: 1000,
            from: address(0x5678),
            to: address(0x9abc)
        });
    }

    function testInitialState() public view {
        assertEq(_wrapper.getNonce(), 0);
    }

    function testAuthorizeBasic() public {
        uint248 expectedNonce = 1;
        bytes32 expectedHash = _wrapper.generateTransactionHash(_sampleTransaction, expectedNonce);

        _wrapper.authorize(_sampleTransaction);

        assertEq(_wrapper.getNonce(), expectedNonce);
        assertEq(_wrapper.getTransactionNonce(expectedHash), expectedNonce);
    }

    function testAuthorizeIncrementsNonce() public {
        _wrapper.authorize(_sampleTransaction);
        assertEq(_wrapper.getNonce(), 1);

        _wrapper.authorize(_sampleTransaction);
        assertEq(_wrapper.getNonce(), 2);

        _wrapper.authorize(_sampleTransaction);
        assertEq(_wrapper.getNonce(), 3);
    }

    function testAuthorizeMultipleTransactions() public {
        PendingPayment.Transaction memory transaction1 = PendingPayment.Transaction({
            asset: address(0x1111),
            amount: 100,
            from: address(0x2222),
            to: address(0x3333)
        });

        PendingPayment.Transaction memory transaction2 = PendingPayment.Transaction({
            asset: address(0x4444),
            amount: 200,
            from: address(0x5555),
            to: address(0x6666)
        });

        bytes32 hash1 = _wrapper.generateTransactionHash(transaction1, 1);
        bytes32 hash2 = _wrapper.generateTransactionHash(transaction2, 2);

        _wrapper.authorize(transaction1);
        _wrapper.authorize(transaction2);

        assertEq(_wrapper.getNonce(), 2);
        assertEq(_wrapper.getTransactionNonce(hash1), 1);
        assertEq(_wrapper.getTransactionNonce(hash2), 2);
    }

    function testAuthorizeWithDifferentChainId() public {
        uint256 originalChainId = block.chainid;

        bytes32 hash1 = _wrapper.generateTransactionHash(_sampleTransaction, 1);
        _wrapper.authorize(_sampleTransaction);

        vm.chainId(999);

        bytes32 hash2 = _wrapper.generateTransactionHash(_sampleTransaction, 2);
        _wrapper.authorize(_sampleTransaction);

        assertNotEq(hash1, hash2);
        assertEq(_wrapper.getTransactionNonce(hash1), 1);
        assertEq(_wrapper.getTransactionNonce(hash2), 2);

        vm.chainId(originalChainId);
    }

    function testAuthorizeWithZeroValues() public {
        PendingPayment.Transaction memory zeroTransaction =
            PendingPayment.Transaction({asset: ZERO_ADDRESS, amount: 0, from: ZERO_ADDRESS, to: ZERO_ADDRESS});

        bytes32 expectedHash = _wrapper.generateTransactionHash(zeroTransaction, 1);

        _wrapper.authorize(zeroTransaction);

        assertEq(_wrapper.getNonce(), 1);
        assertEq(_wrapper.getTransactionNonce(expectedHash), 1);
    }

    function testAuthorizeWithMaxValues() public {
        // solhint-disable-next-line gas-small-strings
        PendingPayment.Transaction memory maxTransaction = PendingPayment.Transaction({
            asset: address(type(uint160).max),
            amount: type(uint248).max,
            from: address(type(uint160).max),
            to: address(type(uint160).max)
        });

        bytes32 expectedHash = _wrapper.generateTransactionHash(maxTransaction, 1);

        _wrapper.authorize(maxTransaction);

        assertEq(_wrapper.getNonce(), 1);
        assertEq(_wrapper.getTransactionNonce(expectedHash), 1);
    }

    function testTransactionHashUniqueness() public view {
        bytes32 hash1 = _wrapper.generateTransactionHash(_sampleTransaction, 1);
        bytes32 hash2 = _wrapper.generateTransactionHash(_sampleTransaction, 2);

        assertNotEq(hash1, hash2);

        PendingPayment.Transaction memory differentTransaction = PendingPayment.Transaction({
            asset: address(0x1234),
            amount: 2000,
            from: address(0x5678),
            to: address(0x9abc)
        });

        bytes32 hash3 = _wrapper.generateTransactionHash(differentTransaction, 1);
        assertNotEq(hash1, hash3);
    }

    function testNonceOverflow() public {
        _wrapper.setNonce(type(uint248).max - 1);

        _wrapper.authorize(_sampleTransaction);
        assertEq(_wrapper.getNonce(), type(uint248).max);

        vm.expectRevert();
        _wrapper.authorize(_sampleTransaction);
    }

    function testFuzzAuthorize(address asset, uint248 amount, address from, address to) public {
        PendingPayment.Transaction memory fuzzTransaction =
            PendingPayment.Transaction({asset: asset, amount: amount, from: from, to: to});

        bytes32 expectedHash = _wrapper.generateTransactionHash(fuzzTransaction, 1);

        _wrapper.authorize(fuzzTransaction);

        assertEq(_wrapper.getNonce(), 1);
        assertEq(_wrapper.getTransactionNonce(expectedHash), 1);
    }

    function testCompleteAuthorizedTransaction() public {
        bytes32 transactionHash = _wrapper.generateTransactionHash(_sampleTransaction, 1);
        _wrapper.authorize(_sampleTransaction);

        assertEq(_wrapper.getTransactionNonce(transactionHash), 1);

        _wrapper.completeAuthorizedTransaction(_sampleTransaction, transactionHash);

        assertEq(_wrapper.getTransactionNonce(transactionHash), 0);
    }

    function testCompleteAuthorizedTransactionNotAuthorized() public {
        bytes32 transactionHash = _wrapper.generateTransactionHash(_sampleTransaction, 1);

        vm.expectRevert(PendingPayment.TransactionNotAuthorized.selector);
        _wrapper.completeAuthorizedTransaction(_sampleTransaction, transactionHash);
    }

    function testCompleteAuthorizedTransactionHashMismatch() public {
        bytes32 transactionHash = _wrapper.generateTransactionHash(_sampleTransaction, 1);
        _wrapper.authorize(_sampleTransaction);

        PendingPayment.Transaction memory differentTransaction = PendingPayment.Transaction({
            asset: address(0x1234),
            amount: 2000,
            from: address(0x5678),
            to: address(0x9abc)
        });

        vm.expectRevert(PendingPayment.TransactionHashMismatch.selector);
        _wrapper.completeAuthorizedTransaction(differentTransaction, transactionHash);
    }

    function testCompleteAuthorizedTransactionMultiple() public {
        bytes32 hash1 = _wrapper.generateTransactionHash(_sampleTransaction, 1);
        _wrapper.authorize(_sampleTransaction);

        PendingPayment.Transaction memory transaction2 = PendingPayment.Transaction({
            asset: address(0x1111),
            amount: 200,
            from: address(0x2222),
            to: address(0x3333)
        });
        bytes32 hash2 = _wrapper.generateTransactionHash(transaction2, 2);
        _wrapper.authorize(transaction2);

        assertEq(_wrapper.getTransactionNonce(hash1), 1);
        assertEq(_wrapper.getTransactionNonce(hash2), 2);

        _wrapper.completeAuthorizedTransaction(_sampleTransaction, hash1);
        assertEq(_wrapper.getTransactionNonce(hash1), 0);
        assertEq(_wrapper.getTransactionNonce(hash2), 2);

        _wrapper.completeAuthorizedTransaction(transaction2, hash2);
        assertEq(_wrapper.getTransactionNonce(hash2), 0);
    }

    function testCompleteAuthorizedTransactionAlreadyCompleted() public {
        bytes32 transactionHash = _wrapper.generateTransactionHash(_sampleTransaction, 1);
        _wrapper.authorize(_sampleTransaction);

        _wrapper.completeAuthorizedTransaction(_sampleTransaction, transactionHash);

        vm.expectRevert(PendingPayment.TransactionNotAuthorized.selector);
        _wrapper.completeAuthorizedTransaction(_sampleTransaction, transactionHash);
    }
}
