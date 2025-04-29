// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {ZKPayV2} from "./mocks/ZKPayV2.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {QueryLogic} from "../src/libraries/QueryLogic.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IZKPay} from "../src/interfaces/IZKPay.sol";
import {NATIVE_ADDRESS, ZERO_ADDRESS, MAX_GAS_CLIENT_CALLBACK} from "../src/libraries/Constants.sol";
import {IZKPayClient} from "../src/interfaces/IZKPayClient.sol";
import {MockCustomLogic} from "./mocks/MockCustomLogic.sol";
import {RejectEther} from "./mocks/RejectEther.sol";

contract ZKPayTest is Test, IZKPayClient {
    ZKPay public zkpay;
    address public _owner;
    address public _treasury;
    address public _priceFeed;
    AssetManagement.PaymentAsset public paymentAssetInstance;

    event CallbackCalled(bytes32 queryHash, bytes queryResult, bytes callbackData);

    function setUp() public {
        _owner = vm.addr(0x1);
        _treasury = vm.addr(0x2);

        _priceFeed = address(new MockV3Aggregator(8, 1000));
        vm.prank(_owner);
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol", _owner, abi.encodeCall(ZKPay.initialize, (_owner, _treasury, _priceFeed, 18, 1000))
        );

        zkpay = ZKPay(zkPayProxyAddress);

        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: _priceFeed,
            tokenDecimals: 18,
            stalePriceThresholdInSeconds: 1000
        });
    }

    function testInitiateTreasuryAddress() public view {
        assertEq(zkpay.getTreasury(), _treasury);
    }

    function testFuzzSetTreasury(address treasury) public {
        vm.prank(_owner);

        if (treasury == ZERO_ADDRESS) {
            vm.expectRevert();
        } else if (treasury == _treasury) {
            vm.expectRevert();
        }

        zkpay.setTreasury(treasury);

        if (treasury != ZERO_ADDRESS && treasury != _treasury) {
            assertEq(zkpay.getTreasury(), treasury);
        }
    }

    function testSetTreasuryCanNotBeZeroAddress() public {
        vm.prank(_owner);
        vm.expectRevert(ZKPay.TreasuryAddressCannotBeZero.selector);
        zkpay.setTreasury(ZERO_ADDRESS);
    }

    function testOwnershipTransfer() public {
        vm.prank(_owner);
        zkpay.transferOwnership(address(0x4));

        assertEq(zkpay.owner(), address(0x4));
    }

    function testOnlyOwnerCanTransferOwnership() public {
        vm.prank(address(0x5));
        vm.expectRevert();
        zkpay.transferOwnership(address(0x6));
    }

    function testTreasuryAddressCanNotBeSameAsCurrent() public {
        vm.prank(_owner);
        vm.expectRevert(ZKPay.TreasuryAddressSameAsCurrent.selector);
        zkpay.setTreasury(_treasury);
    }

    function testTransparentUpgrade() public {
        address proxy = Upgrades.deployTransparentProxy(
            "ZKPay.sol", msg.sender, abi.encodeCall(ZKPay.initialize, (msg.sender, _treasury, _priceFeed, 18, 1000))
        );
        address implAddressV1 = Upgrades.getImplementationAddress(proxy);
        address adminAddress = Upgrades.getAdminAddress(proxy);

        assertFalse(adminAddress == ZERO_ADDRESS);

        Upgrades.upgradeProxy(proxy, "ZKPayV2.sol", abi.encodeCall(ZKPayV2.initialize, (msg.sender)), msg.sender);
        address implAddressV2 = Upgrades.getImplementationAddress(proxy);

        assertEq(Upgrades.getAdminAddress(proxy), adminAddress);

        assertFalse(implAddressV2 == implAddressV1);

        assertEq(ZKPayV2(implAddressV2).getVersion(), 2);
    }

    function testOnlyOwnerCanSetTreasury() public {
        vm.prank(address(0x3));
        vm.expectRevert();
        zkpay.setTreasury(address(0x3));
    }

    function testFuzzOnlyOwnerCanSetTreasury(address caller) public {
        vm.prank(caller);

        if (caller != _owner) {
            vm.expectRevert();
        }
        zkpay.setTreasury(caller);
    }

    function testFuzzSetPaymentAsset(
        address asset,
        bytes1 allowedPaymentTypes,
        uint8 tokenDecimals,
        uint64 stalePriceThresholdInSeconds
    ) public {
        vm.prank(_owner);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(
            asset, allowedPaymentTypes, _priceFeed, tokenDecimals, stalePriceThresholdInSeconds
        );

        zkpay.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: allowedPaymentTypes,
                priceFeed: _priceFeed,
                tokenDecimals: tokenDecimals,
                stalePriceThresholdInSeconds: stalePriceThresholdInSeconds
            })
        );
    }

    function testSetPaymentAsset(address asset) public {
        vm.assume(asset != NATIVE_ADDRESS);
        vm.prank(_owner);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(
            asset, AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG, _priceFeed, 18, 1000
        );

        zkpay.setPaymentAsset(asset, paymentAssetInstance);
    }

    function testFuzzOnlyOwnerCanSetPaymentAsset(address caller) public {
        vm.prank(caller);

        if (caller != _owner) {
            vm.expectRevert();
        }

        zkpay.setPaymentAsset(address(0x4), paymentAssetInstance);
    }

    function testRemovePaymentAsset() public {
        vm.startPrank(_owner);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetRemoved(address(0x100));

        zkpay.removePaymentAsset(address(0x100));

        vm.expectRevert(AssetManagement.AssetNotFound.selector);
        zkpay.getPaymentAsset(address(0x100));
    }

    function testFuzzOnlyOwnerCanRemovePaymentAsset(address caller) public {
        vm.prank(caller);

        if (caller != _owner) {
            vm.expectRevert();
        }

        zkpay.removePaymentAsset(address(0x100));
    }

    function testGetPaymentAsset() public {
        vm.prank(_owner);

        AssetManagement.PaymentAsset memory paymentAsset = zkpay.getPaymentAsset(NATIVE_ADDRESS);
        assertEq(paymentAsset.allowedPaymentTypes, AssetManagement.NONE_PAYMENT_FLAG);
        assertEq(paymentAsset.priceFeed, _priceFeed);
        assertEq(paymentAsset.tokenDecimals, 18);
        assertEq(paymentAsset.stalePriceThresholdInSeconds, 1000);
    }

    function testQuery() public {
        uint248 usdcAmount = 10e6;

        // deploy usdc
        uint8 usdcDecimals = 6;
        MockERC20 usdc = new MockERC20();
        usdc.mint(address(this), 100e6); // 100 usdc

        // deploy mock price feed
        address mockUsdcPriceFeed = address(new MockV3Aggregator(8, 1e8));

        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: mockUsdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: 1000
        });

        vm.prank(_owner);
        zkpay.setPaymentAsset(address(usdc), paymentAssetInstance);

        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: address(this),
            callbackGasLimit: 1000000,
            callbackData: "test",
            customLogicContractAddress: address(this)
        });

        // allow the zkpay contract to transfer usdc
        usdc.approve(address(zkpay), usdcAmount);

        uint248 queryNonce = 1;

        // query
        QueryLogic.QueryPayment memory payment =
            QueryLogic.QueryPayment({asset: address(usdc), amount: usdcAmount, source: address(this)});

        bytes32 expectedQueryHash =
            keccak256(abi.encode(block.chainid, address(zkpay), queryNonce, queryRequest, payment));

        vm.expectEmit(true, true, true, true);
        emit QueryLogic.QueryReceived(
            queryNonce,
            address(this),
            queryRequest.query,
            queryRequest.queryParameters,
            queryRequest.timeout,
            queryRequest.callbackClientContractAddress,
            queryRequest.callbackGasLimit,
            queryRequest.callbackData,
            queryRequest.customLogicContractAddress,
            expectedQueryHash
        );

        uint248 usdcDecimalsIn18Decimals = uint248(usdcAmount) * uint248(10 ** (18 - usdcDecimals));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.NewQueryPayment(
            expectedQueryHash, address(usdc), usdcAmount, address(this), usdcDecimalsIn18Decimals
        );

        zkpay.query(address(usdc), usdcAmount, queryRequest);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.query(address(0x0123), usdcAmount, queryRequest);

        usdc.approve(address(zkpay), usdcAmount);
        vm.warp(block.timestamp + 101);
        vm.expectRevert(QueryLogic.InvalidQueryTimeout.selector);
        zkpay.query(address(usdc), usdcAmount, queryRequest);
    }

    function zkPayCallback(bytes32 queryHash, bytes calldata queryResult, bytes calldata callbackData) external {
        emit CallbackCalled(queryHash, queryResult, callbackData);
    }

    function testFuzzValidateQueryRequest(bytes32 queryHashFuzzValue) public {
        uint248 usdcAmount = 10e6;

        // deploy usdc
        uint8 usdcDecimals = 6;
        MockERC20 usdc = new MockERC20();
        usdc.mint(address(this), 100e6); // 100 usdc

        // deploy mock price feed
        address mockUsdcPriceFeed = address(new MockV3Aggregator(8, 1e8));

        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: mockUsdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: 1000
        });

        vm.prank(_owner);
        zkpay.setPaymentAsset(address(usdc), paymentAssetInstance);

        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: address(this),
            callbackGasLimit: 1000000,
            callbackData: "test",
            customLogicContractAddress: address(this)
        });

        vm.expectRevert(ZKPay.InvalidQueryHash.selector);
        zkpay.validateQueryRequest(queryHashFuzzValue, queryRequest);

        // allow the zkpay contract to spend usdc
        usdc.approve(address(zkpay), usdcAmount);

        bytes32 queryHash = zkpay.query(address(usdc), usdcAmount, queryRequest);

        QueryLogic.QueryRequest memory queryRequest2 = QueryLogic.QueryRequest({
            query: "new query",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: address(this),
            callbackGasLimit: 1000000,
            callbackData: "test",
            customLogicContractAddress: address(this)
        });

        vm.expectRevert(ZKPay.InvalidQueryHash.selector);
        zkpay.validateQueryRequest(queryHash, queryRequest2);

        // shouldn't revert, as it's a valid request
        zkpay.validateQueryRequest(queryHash, queryRequest);
    }

    function testFulfillQuery() public {
        // deploy usdc
        uint8 usdcDecimals = 6;
        MockERC20 usdc = new MockERC20();
        usdc.mint(address(this), 100e6); // 100 usdc

        // paying 10 usdc
        uint248 usdcAmount = 10e6;

        // deploy mock price feed
        address mockUsdcPriceFeed = address(new MockV3Aggregator(8, 1e8)); // 1e8 = 1 USD

        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: mockUsdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: 1000
        });

        vm.prank(_owner);
        zkpay.setPaymentAsset(address(usdc), paymentAssetInstance);

        // deploy custom logic contract
        MockCustomLogic mockedCustomLogic = new MockCustomLogic();

        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
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
        bytes32 queryHash = zkpay.query(address(usdc), usdcAmount, queryRequest);

        // fulfill query
        vm.expectEmit(true, true, true, true);
        emit IZKPay.CallbackSucceeded(queryHash, address(this));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.QueryFulfilled(queryHash);
        zkpay.fulfillQuery(queryHash, queryRequest, "results");
    }

    function testCallbackGasLimitTooHigh() public {
        // deploy usdc
        uint8 usdcDecimals = 6;
        MockERC20 usdc = new MockERC20();
        usdc.mint(address(this), 100e6); // 100 usdc

        // paying 10 usdc
        uint248 usdcAmount = 10e6;

        // deploy mock price feed
        address mockUsdcPriceFeed = address(new MockV3Aggregator(8, 1e8)); // 1e8 = 1 USD

        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: mockUsdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: 1000
        });

        vm.prank(_owner);
        zkpay.setPaymentAsset(address(usdc), paymentAssetInstance);

        // deploy custom logic contract
        MockCustomLogic mockedCustomLogic = new MockCustomLogic();

        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: address(this),
            callbackGasLimit: uint64(MAX_GAS_CLIENT_CALLBACK + 1),
            callbackData: "test",
            customLogicContractAddress: address(mockedCustomLogic)
        });

        // allow the zkpay contract to transfer usdc
        usdc.approve(address(zkpay), usdcAmount);

        // query
        vm.expectRevert(QueryLogic.CallbackGasLimitTooHigh.selector);
        zkpay.query(address(usdc), usdcAmount, queryRequest);
    }

    function testPayNativeExceedsUint248Limit() public {
        // Set up initial state
        address onBehalfOfAddr = address(0x123);
        bytes32 onBehalfOf = bytes32(uint256(uint160(onBehalfOfAddr)));
        address target = address(0x456);
        uint64 itemId = 789;
        bytes memory memo = abi.encode(itemId);
        uint256 excessiveAmount = uint256(type(uint248).max) + 1;

        // Fund the test contract
        vm.deal(address(this), excessiveAmount);

        // Expect revert due to excessive amount
        vm.expectRevert(ZKPay.ValueExceedsUint248Limit.selector);
        zkpay.sendNative{value: excessiveAmount}(onBehalfOf, target, memo);
    }

    // Use the RejectEther contract defined outside this contract
    function testPayNativeFailedTransfer() public {
        // Set up initial state
        address onBehalfOfAddr = address(0x123);
        bytes32 onBehalfOf = bytes32(uint256(uint160(onBehalfOfAddr)));
        uint64 itemId = 789;
        bytes memory memo = abi.encode(itemId);
        uint248 amount = 1 ether;

        vm.prank(_owner);
        zkpay.setPaymentAsset(NATIVE_ADDRESS, paymentAssetInstance);

        // Create a contract that will reject ETH transfers
        RejectEther rejector = new RejectEther();

        // Use the rejector as the target address
        address rejectingTarget = address(rejector);

        // Fund the test contract
        vm.deal(address(this), amount);

        // Expect revert due to failed transfer
        vm.expectRevert(AssetManagement.NativePaymentFailed.selector);
        zkpay.sendNative{value: amount}(onBehalfOf, rejectingTarget, memo);
    }
}
