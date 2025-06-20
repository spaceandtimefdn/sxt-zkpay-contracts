// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {QueryLogic} from "../../src/libraries/QueryLogic.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {MockCustomLogic} from "../mocks/MockCustomLogic.sol";
import {NATIVE_ADDRESS, MAX_GAS_CLIENT_CALLBACK} from "../../src/libraries/Constants.sol";
import {ICustomLogic} from "../../src/interfaces/ICustomLogic.sol";
import {Setup} from "./Setup.sol";

contract QueryLogicWrapperWithoutReceive {
    mapping(address asset => AssetManagement.PaymentAsset) internal _assets;
    mapping(bytes32 queryHash => QueryLogic.QueryPayment payment) public _queryPayments;
    mapping(bytes32 queryHash => uint248 queryNonce) public _queryNonces;

    address internal _usdcAddress;
    bytes32 public _nativeQueryHash;
    bytes32 public _erc20QueryHash;

    constructor() {
        _usdcAddress = address(new MockERC20());

        Setup.setupAssets(_assets, _usdcAddress);
        _nativeQueryHash = bytes32(uint256(0x01));
        _erc20QueryHash = bytes32(uint256(0x02));

        _queryPayments[_nativeQueryHash] =
            QueryLogic.QueryPayment({asset: NATIVE_ADDRESS, amount: 0.01 ether, source: address(this)});
        _queryPayments[_erc20QueryHash] =
            QueryLogic.QueryPayment({asset: _usdcAddress, amount: 10e6, source: address(this)});

        _queryNonces[_nativeQueryHash] = 1;
        _queryNonces[_erc20QueryHash] = 2;
    }

    function getUsdcAddress() public view returns (address) {
        return _usdcAddress;
    }

    function settleQueryPayment(
        address customLogicContractAddress,
        uint248 gasUsed,
        QueryLogic.QueryPayment calldata payment
    ) external returns (uint248 paidAmount, uint248 refundAmount) {
        (paidAmount, refundAmount) =
            QueryLogic.settleQueryPayment(_assets, customLogicContractAddress, gasUsed, payment);
    }

    function cancelQuery(bytes32 queryHash) external {
        QueryLogic.cancelQuery(_queryPayments, _queryNonces, queryHash);
    }

    function generateQueryHash(
        uint248 queryNonce,
        QueryLogic.QueryRequest calldata queryRequest,
        QueryLogic.QueryPayment calldata payment
    ) external view returns (bytes32 queryHash) {
        queryHash = QueryLogic.generateQueryHash(queryNonce, queryRequest, payment);
    }
}

contract QueryLogicWrapperWithReceive is QueryLogicWrapperWithoutReceive {
    receive() external payable {}
}

contract QueryLogicTest is Test {
    uint248[1] internal _queryNonce;
    mapping(bytes32 queryHash => uint248 queryNonce) internal _queryNonces;
    mapping(bytes32 queryHash => uint64 querySubmissionTimestamp) internal _querySubmissionTimestamps;

    /// forge-config: default.allow_internal_expect_revert = true
    function testFuzzSubmitQuery(QueryLogic.QueryRequest calldata queryRequest, QueryLogic.QueryPayment memory payment)
        public
    {
        vm.assume(queryRequest.callbackGasLimit < MAX_GAS_CLIENT_CALLBACK);
        uint256 timestamp = block.timestamp + 10000;
        vm.warp(timestamp);

        if (queryRequest.callbackClientContractAddress != msg.sender) {
            vm.expectRevert(QueryLogic.CallbackClientAddressShouldBeMsgSender.selector);
        } else if (queryRequest.timeout != 0 && queryRequest.timeout < timestamp) {
            vm.expectRevert(QueryLogic.InvalidQueryTimeout.selector);
        }

        vm.prank(msg.sender);
        QueryLogic.submitQuery(_queryNonce, _queryNonces, _querySubmissionTimestamps, queryRequest, payment);
    }

    function testSettleQueryPayment() public {
        uint248 paymentAmount = 10e6;

        QueryLogicWrapperWithReceive wrapper = new QueryLogicWrapperWithReceive();
        address usdc = wrapper.getUsdcAddress();
        MockERC20(usdc).mint(address(wrapper), paymentAmount);

        address customLogicContractAddress = address(new MockCustomLogic());
        uint248 gasUsed = 1_000_000;
        QueryLogic.QueryPayment memory payment =
            QueryLogic.QueryPayment({asset: usdc, amount: paymentAmount, source: address(wrapper)});

        wrapper.settleQueryPayment(customLogicContractAddress, gasUsed, payment);

        (address merchantAddress,) = ICustomLogic(customLogicContractAddress).getMerchantAddressAndFee();

        assertLt(MockERC20(usdc).balanceOf(address(wrapper)), paymentAmount);
        assertGt(MockERC20(usdc).balanceOf(merchantAddress), 0);
    }

    function testSettleQueryPaymentWithUsdc() public {
        QueryLogicWrapperWithReceive wrapper = new QueryLogicWrapperWithReceive();

        uint248 paymentAmount = 10e6;
        address usdcAddress = wrapper.getUsdcAddress();

        MockERC20(usdcAddress).mint(address(wrapper), paymentAmount);

        address customLogicContractAddress = address(new MockCustomLogic());
        uint248 gasUsed = 1_000_000;
        QueryLogic.QueryPayment memory payment =
            QueryLogic.QueryPayment({asset: usdcAddress, amount: paymentAmount, source: address(wrapper)});

        wrapper.settleQueryPayment(customLogicContractAddress, gasUsed, payment);

        (address merchantAddress,) = ICustomLogic(customLogicContractAddress).getMerchantAddressAndFee();

        assertLt(MockERC20(usdcAddress).balanceOf(address(wrapper)), paymentAmount);
        assertGt(MockERC20(usdcAddress).balanceOf(merchantAddress), 0);
    }

    function testPayoutAmountExceedsPaymentAmount() public {
        uint248 paymentAmount = 10;

        QueryLogicWrapperWithReceive wrapper = new QueryLogicWrapperWithReceive();
        address usdc = wrapper.getUsdcAddress();
        MockERC20(usdc).mint(address(wrapper), paymentAmount);

        address customLogicContractAddress = address(new MockCustomLogic());
        uint248 gasUsed = 1_000_000;
        QueryLogic.QueryPayment memory payment =
            QueryLogic.QueryPayment({asset: usdc, amount: paymentAmount, source: address(wrapper)});

        wrapper.settleQueryPayment(customLogicContractAddress, gasUsed, payment);

        (address merchantAddress,) = ICustomLogic(customLogicContractAddress).getMerchantAddressAndFee();

        assertEq(MockERC20(usdc).balanceOf(address(wrapper)), 0);
        assertEq(MockERC20(usdc).balanceOf(merchantAddress), paymentAmount);
    }

    function testQueryLogicCancelQuery() public {
        QueryLogicWrapperWithReceive wrapper = new QueryLogicWrapperWithReceive();
        address usdcAddress = wrapper.getUsdcAddress();
        vm.deal(address(wrapper), 0.01 ether);
        MockERC20(usdcAddress).mint(address(wrapper), 10e6);

        bytes32 erc20QueryHash = wrapper._erc20QueryHash();
        wrapper.cancelQuery(erc20QueryHash);
    }

    function testGenerateQueryHashIncludesContractAddress() public {
        // Create a wrapper to test the hash generation
        QueryLogicWrapperWithReceive wrapper = new QueryLogicWrapperWithReceive();

        // Create a second wrapper to verify different contract addresses generate different hashes
        QueryLogicWrapperWithReceive wrapper2 = new QueryLogicWrapperWithReceive();

        // Create identical query parameters
        uint248 queryNonce = 1;
        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "params",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: address(this),
            callbackGasLimit: 1_000_000,
            callbackData: "data",
            customLogicContractAddress: address(this)
        });

        QueryLogic.QueryPayment memory payment =
            QueryLogic.QueryPayment({asset: address(0x100), amount: 1 ether, source: address(wrapper)});

        // Use the exposed generateQueryHash function to generate hashes from both wrappers
        bytes32 hash1 = wrapper.generateQueryHash(queryNonce, queryRequest, payment);
        bytes32 hash2 = wrapper2.generateQueryHash(queryNonce, queryRequest, payment);

        // Verify that identical query parameters generate different hashes when called from different contracts
        assertNotEq(hash1, hash2);
    }
}
