// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PoSQLVerifier} from "../src/PoSQLVerifier.sol";
import {QueryLogic} from "../src/libraries/QueryLogic.sol";

contract PoSQLVerifierTest is Test {
    PoSQLVerifier public verifier;
    address public merchantAddress;
    address public owner;

    event Execute(QueryLogic.QueryRequest queryRequest, bytes queryResult, address merchantAddress);

    // Add receive function to allow the test contract to receive ETH
    receive() external payable {}

    function setUp() public {
        owner = address(this);
        merchantAddress = address(0x123);
        verifier = new PoSQLVerifier(merchantAddress);
    }

    function testConstructor() public view {
        // Test that the constructor sets the payout address correctly
        assertEq(verifier.MERCHANT_ADDRESS(), merchantAddress);
    }

    function testConstructorZeroAddressReverts() public {
        // Test that the constructor reverts when given a zero address
        vm.expectRevert(PoSQLVerifier.ZeroAddressNotAllowed.selector);
        new PoSQLVerifier(address(0));
    }

    function testReceiveFunction() public {
        // Test the receive function by sending ETH to the contract
        uint256 initialBalance = address(verifier).balance;
        uint256 amountToSend = 1 ether;

        // Send ETH to the contract
        (bool success,) = address(verifier).call{value: amountToSend}("");

        // Verify the transaction was successful
        assertTrue(success);

        // Verify the contract balance increased
        assertEq(address(verifier).balance, initialBalance + amountToSend);
    }

    function testGetMerchantAddressAndFee() public view {
        // Test the getMerchantAddressAndFee function
        (address returnedMerchantAddress, uint248 fee) = verifier.getMerchantAddressAndFee();

        // Verify the returned payout address matches the one set in the constructor
        assertEq(returnedMerchantAddress, merchantAddress);

        // Verify the fee is 1 USD (1e18)
        assertEq(fee, 1e18);
    }

    function testExecute() public {
        // Create a query request
        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
            query: bytes("SELECT * FROM table"),
            queryParameters: bytes("parameters"),
            timeout: uint64(block.timestamp + 3600),
            callbackClientContractAddress: address(this),
            callbackGasLimit: 100000,
            customLogicContractAddress: address(0),
            callbackData: bytes("callback data")
        });

        bytes memory queryResult = bytes("query result");

        // Expect the Execute event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Execute(queryRequest, queryResult, merchantAddress);

        // Call the execute function
        bytes memory result = verifier.execute(queryRequest, queryResult);

        // Verify the result is the same as the input query result
        assertEq(keccak256(result), keccak256(queryResult));
    }

    function testWithdraw() public {
        // First, send some ETH to the contract
        uint256 amountToSend = 1 ether;
        (bool success,) = address(verifier).call{value: amountToSend}("");
        assertTrue(success);

        // Get the initial balance of the owner
        uint256 initialOwnerBalance = owner.balance;

        // Call withdraw as the owner
        verifier.withdraw();

        // Verify the ETH was transferred to the owner
        assertEq(address(verifier).balance, 0);
        assertEq(owner.balance, initialOwnerBalance + amountToSend);
    }

    function testWithdrawNonOwnerReverts() public {
        // First, send some ETH to the contract
        uint256 amountToSend = 1 ether;
        (bool success,) = address(verifier).call{value: amountToSend}("");
        assertTrue(success);

        // Try to call withdraw as a non-owner
        address nonOwner = address(0x789);
        vm.prank(nonOwner);
        vm.expectRevert(PoSQLVerifier.OnlyOwnerAllowed.selector);
        verifier.withdraw();
    }
}
