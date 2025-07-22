// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {EscrowPayment} from "../../src/libraries/EscrowPayment.sol";

contract EscrowPaymentWrapper {
    EscrowPayment.EscrowPaymentStorage internal _escrowPaymentStorage;

    function authorize(EscrowPayment.Transaction calldata transaction, bytes32 itemId) external {
        EscrowPayment.authorize(_escrowPaymentStorage, transaction, itemId);
    }

    function getNonce() external view returns (uint248) {
        return _escrowPaymentStorage.nonce;
    }

    function getTransactionNonce(bytes32 transactionHash) external view returns (uint248) {
        return _escrowPaymentStorage.transactionNonces[transactionHash];
    }

    function generateTransactionHash(EscrowPayment.Transaction calldata transaction, bytes32 itemId, uint248 nonce)
        external
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(transaction, itemId, nonce, block.chainid));
    }

    function setNonce(uint248 nonce) external {
        _escrowPaymentStorage.nonce = nonce;
    }
}

contract EscrowPaymentTest is Test {
    EscrowPaymentWrapper internal _wrapper;
    EscrowPayment.Transaction internal _sampleTransaction;

    function setUp() public {
        _wrapper = new EscrowPaymentWrapper();

        _sampleTransaction = EscrowPayment.Transaction({
            asset: address(0x1234),
            amount: 1000,
            from: address(0x5678),
            merchant: address(0x9abc),
            memo: "test payment"
        });
    }

    function testInitialState() public view {
        assertEq(_wrapper.getNonce(), 0);
    }

    function testAuthorizeBasic() public {
        uint248 expectedNonce = 1;
        bytes32 itemId = bytes32("item123");
        bytes32 expectedHash = _wrapper.generateTransactionHash(_sampleTransaction, itemId, expectedNonce);

        vm.expectEmit(true, true, true, true);
        emit EscrowPayment.Authorized(_sampleTransaction, expectedNonce, expectedHash);

        _wrapper.authorize(_sampleTransaction, itemId);

        assertEq(_wrapper.getNonce(), expectedNonce);
        assertEq(_wrapper.getTransactionNonce(expectedHash), expectedNonce);
    }

    function testAuthorizeIncrementsNonce() public {
        bytes32 itemId = bytes32("item123");

        _wrapper.authorize(_sampleTransaction, itemId);
        assertEq(_wrapper.getNonce(), 1);

        _wrapper.authorize(_sampleTransaction, itemId);
        assertEq(_wrapper.getNonce(), 2);

        _wrapper.authorize(_sampleTransaction, itemId);
        assertEq(_wrapper.getNonce(), 3);
    }

    function testAuthorizeMultipleTransactions() public {
        EscrowPayment.Transaction memory transaction1 = EscrowPayment.Transaction({
            asset: address(0x1111),
            amount: 100,
            from: address(0x2222),
            merchant: address(0x3333),
            memo: "tx1"
        });

        EscrowPayment.Transaction memory transaction2 = EscrowPayment.Transaction({
            asset: address(0x4444),
            amount: 200,
            from: address(0x5555),
            merchant: address(0x6666),
            memo: "tx2"
        });

        bytes32 itemId1 = bytes32("item1");
        bytes32 itemId2 = bytes32("item2");
        bytes32 hash1 = _wrapper.generateTransactionHash(transaction1, itemId1, 1);
        bytes32 hash2 = _wrapper.generateTransactionHash(transaction2, itemId2, 2);

        vm.expectEmit(true, true, true, true);
        emit EscrowPayment.Authorized(transaction1, 1, hash1);
        _wrapper.authorize(transaction1, itemId1);

        vm.expectEmit(true, true, true, true);
        emit EscrowPayment.Authorized(transaction2, 2, hash2);
        _wrapper.authorize(transaction2, itemId2);

        assertEq(_wrapper.getNonce(), 2);
        assertEq(_wrapper.getTransactionNonce(hash1), 1);
        assertEq(_wrapper.getTransactionNonce(hash2), 2);
    }

    function testAuthorizeWithDifferentChainId() public {
        uint256 originalChainId = block.chainid;
        bytes32 itemId = bytes32("item123");

        bytes32 hash1 = _wrapper.generateTransactionHash(_sampleTransaction, itemId, 1);
        _wrapper.authorize(_sampleTransaction, itemId);

        vm.chainId(999);

        bytes32 hash2 = _wrapper.generateTransactionHash(_sampleTransaction, itemId, 2);
        _wrapper.authorize(_sampleTransaction, itemId);

        assertNotEq(hash1, hash2);
        assertEq(_wrapper.getTransactionNonce(hash1), 1);
        assertEq(_wrapper.getTransactionNonce(hash2), 2);

        vm.chainId(originalChainId);
    }

    function testAuthorizeWithZeroValues() public {
        EscrowPayment.Transaction memory zeroTransaction =
            EscrowPayment.Transaction({asset: address(0), amount: 0, from: address(0), merchant: address(0), memo: ""});

        bytes32 zeroItemId = bytes32(0);
        bytes32 expectedHash = _wrapper.generateTransactionHash(zeroTransaction, zeroItemId, 1);

        vm.expectEmit(true, true, true, true);
        emit EscrowPayment.Authorized(zeroTransaction, 1, expectedHash);

        _wrapper.authorize(zeroTransaction, zeroItemId);

        assertEq(_wrapper.getNonce(), 1);
        assertEq(_wrapper.getTransactionNonce(expectedHash), 1);
    }

    function testAuthorizeWithMaxValues() public {
        // solhint-disable-next-line gas-small-strings
        EscrowPayment.Transaction memory maxTransaction = EscrowPayment.Transaction({
            asset: address(type(uint160).max),
            amount: type(uint248).max,
            from: address(type(uint160).max),
            merchant: address(type(uint160).max),
            memo: "maximum length memo that could be very long"
        });

        bytes32 maxItemId = bytes32(type(uint256).max);
        bytes32 expectedHash = _wrapper.generateTransactionHash(maxTransaction, maxItemId, 1);

        vm.expectEmit(true, true, true, true);
        emit EscrowPayment.Authorized(maxTransaction, 1, expectedHash);

        _wrapper.authorize(maxTransaction, maxItemId);

        assertEq(_wrapper.getNonce(), 1);
        assertEq(_wrapper.getTransactionNonce(expectedHash), 1);
    }

    function testAuthorizeWithLongMemo() public {
        // solhint-disable-next-line gas-small-strings
        string memory longMemo =
            "This is a very long memo that contains a lot of text to test the handling of long memo fields in the transaction structure and to ensure it works correctly with the authorization process";

        EscrowPayment.Transaction memory longMemoTransaction = EscrowPayment.Transaction({
            asset: address(0x1234),
            amount: 5000,
            from: address(0x5678),
            merchant: address(0x9abc),
            memo: bytes(longMemo)
        });

        bytes32 longMemoItemId = bytes32("longmemo");
        bytes32 expectedHash = _wrapper.generateTransactionHash(longMemoTransaction, longMemoItemId, 1);

        vm.expectEmit(true, true, true, true);
        emit EscrowPayment.Authorized(longMemoTransaction, 1, expectedHash);

        _wrapper.authorize(longMemoTransaction, longMemoItemId);

        assertEq(_wrapper.getNonce(), 1);
        assertEq(_wrapper.getTransactionNonce(expectedHash), 1);
    }

    function testTransactionHashUniqueness() public view {
        bytes32 itemId = bytes32("item123");
        bytes32 hash1 = _wrapper.generateTransactionHash(_sampleTransaction, itemId, 1);
        bytes32 hash2 = _wrapper.generateTransactionHash(_sampleTransaction, itemId, 2);

        assertNotEq(hash1, hash2);

        EscrowPayment.Transaction memory differentTransaction = EscrowPayment.Transaction({
            asset: address(0x1234),
            amount: 2000,
            from: address(0x5678),
            merchant: address(0x9abc),
            memo: "test payment"
        });

        bytes32 hash3 = _wrapper.generateTransactionHash(differentTransaction, itemId, 1);
        assertNotEq(hash1, hash3);
    }

    function testNonceOverflow() public {
        _wrapper.setNonce(type(uint248).max - 1);

        bytes32 itemId = bytes32("item123");
        _wrapper.authorize(_sampleTransaction, itemId);
        assertEq(_wrapper.getNonce(), type(uint248).max);

        vm.expectRevert();
        _wrapper.authorize(_sampleTransaction, itemId);
    }

    function testFuzzAuthorize(
        address asset,
        uint248 amount,
        address from,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) public {
        EscrowPayment.Transaction memory fuzzTransaction =
            EscrowPayment.Transaction({asset: asset, amount: amount, from: from, merchant: merchant, memo: memo});

        bytes32 expectedHash = _wrapper.generateTransactionHash(fuzzTransaction, itemId, 1);

        vm.expectEmit(true, true, true, true);
        emit EscrowPayment.Authorized(fuzzTransaction, 1, expectedHash);

        _wrapper.authorize(fuzzTransaction, itemId);

        assertEq(_wrapper.getNonce(), 1);
        assertEq(_wrapper.getTransactionNonce(expectedHash), 1);
    }
}
