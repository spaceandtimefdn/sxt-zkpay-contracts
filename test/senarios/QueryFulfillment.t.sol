// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {ZKPay} from "../../src/ZKPay.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {QueryLogic} from "../../src/libraries/QueryLogic.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IZKPay} from "../../src/interfaces/IZKPay.sol";
import {IZKPayClient} from "../../src/interfaces/IZKPayClient.sol";
import {MockCustomLogic} from "../mocks/MockCustomLogic.sol";
import {FailingClientContract} from "../mocks/FailingClientContract.sol";
import {ICustomLogic} from "../../src/interfaces/ICustomLogic.sol";

contract QueryFulfillmentTest is Test, IZKPayClient {
    ZKPay public zkpay;
    address public _owner;
    address public _treasury;
    address public _nativeTokenPriceFeed;
    AssetManagement.PaymentAsset public paymentAssetInstance;
    MockERC20 public usdc;

    bytes32 public _queryHash;
    QueryLogic.QueryRequest public _queryRequest;

    event CallbackCalled(bytes32 queryHash, bytes queryResult, bytes callbackData);

    function setUp() public {
        uint8 nativeTokenDecimals = 18;
        int256 nativeTokenPrice = 1000e8;
        uint248 usdcAmount = 10e6;

        _owner = vm.addr(0x1);
        _treasury = vm.addr(0x2);

        vm.startPrank(_owner);

        // deploy zkpay
        _nativeTokenPriceFeed = address(new MockV3Aggregator(8, nativeTokenPrice));

        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            _owner,
            abi.encodeCall(ZKPay.initialize, (_owner, _treasury, _nativeTokenPriceFeed, nativeTokenDecimals, 1000))
        );
        zkpay = ZKPay(zkPayProxyAddress);

        // deploy usdc
        uint8 usdcDecimals = 6;
        usdc = new MockERC20();
        usdc.mint(address(this), usdcAmount);

        // deploy mock price feed
        address mockUsdcPriceFeed = address(new MockV3Aggregator(8, 1e8)); // 1e8 = 1 USD

        // usdc
        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: mockUsdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: 1000
        });
        zkpay.setPaymentAsset(address(usdc), paymentAssetInstance);

        vm.stopPrank();

        // deploy custom logic contract
        MockCustomLogic mockedCustomLogic = new MockCustomLogic();

        _queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: address(this),
            callbackGasLimit: 1_000_000,
            callbackData: "test",
            customLogicContractAddress: address(mockedCustomLogic)
        });

        // allow the zkpay contract to transfer usdc
        usdc.approve(address(zkpay), usdcAmount);

        // query
        _queryHash = zkpay.query(address(usdc), usdcAmount, _queryRequest);
    }

    // allow the test contract to receive native tokens as it behave as a client contract
    receive() external payable {}

    function zkPayCallback(bytes32 queryHash, bytes calldata queryResult, bytes calldata callbackData) external {
        emit CallbackCalled(queryHash, queryResult, callbackData);
    }

    function testQueryTimeout() public {
        vm.warp(_queryRequest.timeout + 1);

        vm.expectRevert(ZKPay.QueryTimeout.selector);
        zkpay.fulfillQuery(_queryHash, _queryRequest, "results");
    }

    function testQueryTimeoutExactBoundary() public {
        // Warp to exactly the timeout timestamp
        vm.warp(_queryRequest.timeout);

        // Fulfilling the query should fail at exactly the timeout timestamp
        vm.expectRevert(ZKPay.QueryTimeout.selector);
        zkpay.fulfillQuery(_queryHash, _queryRequest, "results");
    }

    function testInvalidQueryHash() public {
        vm.expectRevert(ZKPay.InvalidQueryHash.selector);
        zkpay.fulfillQuery(bytes32(0), _queryRequest, "results");

        QueryLogic.QueryRequest memory queryRequest2 = QueryLogic.QueryRequest({
            query: "new query",
            queryParameters: _queryRequest.queryParameters,
            timeout: _queryRequest.timeout,
            callbackClientContractAddress: _queryRequest.callbackClientContractAddress,
            callbackGasLimit: _queryRequest.callbackGasLimit,
            callbackData: _queryRequest.callbackData,
            customLogicContractAddress: _queryRequest.customLogicContractAddress
        });

        vm.expectRevert(ZKPay.InvalidQueryHash.selector);
        zkpay.fulfillQuery(_queryHash, queryRequest2, "results");
    }

    function testCallbackFailed() public {
        address callbackClientContractAddress = address(new FailingClientContract());

        QueryLogic.QueryRequest memory queryRequest2 = QueryLogic.QueryRequest({
            query: _queryRequest.query,
            queryParameters: _queryRequest.queryParameters,
            timeout: _queryRequest.timeout,
            callbackClientContractAddress: callbackClientContractAddress,
            callbackGasLimit: _queryRequest.callbackGasLimit,
            callbackData: _queryRequest.callbackData,
            customLogicContractAddress: _queryRequest.customLogicContractAddress
        });

        // mint usdc
        uint248 usdcAmount = 10e6;
        vm.prank(_owner);
        usdc.mint(callbackClientContractAddress, usdcAmount);

        vm.startPrank(callbackClientContractAddress);

        // allow the zkpay contract to transfer usdc
        usdc.approve(address(zkpay), usdcAmount);

        // query
        _queryHash = zkpay.query(address(usdc), usdcAmount, queryRequest2);

        vm.stopPrank();

        // fulfill query
        vm.expectEmit(true, true, true, true);
        emit IZKPay.CallbackFailed(_queryHash, callbackClientContractAddress);
        zkpay.fulfillQuery(_queryHash, queryRequest2, "results");
    }

    function testFulfillUnderPaidQuery() public {
        QueryLogic.QueryRequest memory queryRequest2 = QueryLogic.QueryRequest({
            query: _queryRequest.query,
            queryParameters: _queryRequest.queryParameters,
            timeout: _queryRequest.timeout,
            callbackClientContractAddress: address(this),
            callbackGasLimit: _queryRequest.callbackGasLimit,
            callbackData: _queryRequest.callbackData,
            customLogicContractAddress: _queryRequest.customLogicContractAddress
        });

        // mint usdc
        uint248 usdcAmount = 10;
        vm.prank(_owner);
        usdc.mint(address(this), usdcAmount);

        // allow the zkpay contract to transfer usdc
        usdc.approve(address(zkpay), usdcAmount);

        // query
        _queryHash = zkpay.query(address(usdc), usdcAmount, queryRequest2);

        // fulfill query
        zkpay.fulfillQuery(_queryHash, queryRequest2, "results");

        // check that the merchant received the correct amount
        assertEq(usdc.balanceOf(_queryRequest.customLogicContractAddress), usdcAmount);
    }

    function testCustomLogicMerchantAddress() public {
        (address customLogicMerchantAddress,) =
            ICustomLogic(_queryRequest.customLogicContractAddress).getMerchantAddressAndFee();

        uint256 balanceBefore = usdc.balanceOf(customLogicMerchantAddress);
        zkpay.fulfillQuery(_queryHash, _queryRequest, "results");
        uint256 balanceAfter = usdc.balanceOf(customLogicMerchantAddress);

        assertGt(balanceAfter, balanceBefore, "merchant did not receive payment");
    }

    function testLowCallbackGasLimit() public {
        QueryLogic.QueryRequest memory queryRequest2 = QueryLogic.QueryRequest({
            query: _queryRequest.query,
            queryParameters: _queryRequest.queryParameters,
            timeout: _queryRequest.timeout,
            callbackClientContractAddress: address(this),
            callbackGasLimit: 1000,
            callbackData: _queryRequest.callbackData,
            customLogicContractAddress: _queryRequest.customLogicContractAddress
        });

        // mint usdc
        uint248 usdcAmount = 10e6;
        vm.prank(_owner);
        usdc.mint(address(this), usdcAmount);

        // allow the zkpay contract to transfer usdc
        usdc.approve(address(zkpay), usdcAmount);

        // query
        _queryHash = zkpay.query(address(usdc), usdcAmount, queryRequest2);

        vm.stopPrank();

        // fulfill query
        vm.expectEmit(true, true, true, true);
        emit IZKPay.CallbackFailed(_queryHash, address(this));
        zkpay.fulfillQuery(_queryHash, queryRequest2, "results");
    }
}
