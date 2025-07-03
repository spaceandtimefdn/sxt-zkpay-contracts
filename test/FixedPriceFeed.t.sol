// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FixedPriceFeed} from "../src/libraries/FixedPriceFeed.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {QueryLogic} from "../src/libraries/QueryLogic.sol";
import {MockCustomLogic} from "./mocks/MockCustomLogic.sol";
import {DummyData} from "./data/DummyData.sol";

contract FixedPriceFeedTest is Test {
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
        address sxt = address(new MockERC20());
        vm.prank(_owner);
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            _owner,
            abi.encodeCall(
                ZKPay.initialize, (_owner, _treasury, sxt, _priceFeed, 18, 1000, DummyData.getSwapLogicConfig())
            )
        );

        zkpay = ZKPay(zkPayProxyAddress);

        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: _priceFeed,
            tokenDecimals: 18,
            stalePriceThresholdInSeconds: 1000
        });
    }

    function zkPayCallback(bytes32 queryHash, bytes calldata queryResult, bytes calldata callbackData) external {
        emit CallbackCalled(queryHash, queryResult, callbackData);
    }

    function testFixedPriceFeed() public {
        FixedPriceFeed fixedPriceFeed = new FixedPriceFeed(8, 1e8);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            fixedPriceFeed.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 1e8);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
        assertEq(fixedPriceFeed.decimals(), 8);
        assertEq(fixedPriceFeed.latestAnswer(), 1e8);
    }

    function testSetAssetWithFixedPriceFeed() public {
        vm.startPrank(_owner);

        address asset = address(new MockERC20());
        uint8 tokenDecimals = 18;
        uint64 stalePriceThresholdInSeconds = 1000;
        bytes1 allowedPaymentTypes = AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG;

        FixedPriceFeed fixedPriceFeed = new FixedPriceFeed(8, 1e8);
        address fixedPriceFeedAddress = address(fixedPriceFeed);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(
            asset, allowedPaymentTypes, address(fixedPriceFeed), tokenDecimals, stalePriceThresholdInSeconds
        );

        zkpay.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: allowedPaymentTypes,
                priceFeed: fixedPriceFeedAddress,
                tokenDecimals: tokenDecimals,
                stalePriceThresholdInSeconds: stalePriceThresholdInSeconds
            }),
            DummyData.getOriginAssetPath(asset)
        );

        vm.stopPrank();
    }

    function testSendWithFixedPriceFeed() public {
        vm.startPrank(_owner);

        address asset = address(new MockERC20());
        uint8 tokenDecimals = 18;
        uint64 stalePriceThresholdInSeconds = 1000;
        bytes1 allowedPaymentTypes = AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG;

        FixedPriceFeed fixedPriceFeed = new FixedPriceFeed(8, 1e8);
        address fixedPriceFeedAddress = address(fixedPriceFeed);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(
            asset, allowedPaymentTypes, address(fixedPriceFeed), tokenDecimals, stalePriceThresholdInSeconds
        );

        zkpay.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: allowedPaymentTypes,
                priceFeed: fixedPriceFeedAddress,
                tokenDecimals: tokenDecimals,
                stalePriceThresholdInSeconds: stalePriceThresholdInSeconds
            }),
            DummyData.getOriginAssetPath(asset)
        );

        vm.stopPrank();

        address payer = vm.addr(0x3);
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x3))));
        address target = vm.addr(0x4);
        uint64 itemId = 789;
        bytes memory memo = abi.encode(itemId);
        uint248 amount = 1e18;

        // fund payer
        vm.prank(_owner);
        MockERC20(asset).mint(payer, amount);

        // approve
        vm.prank(payer);
        MockERC20(asset).approve(address(zkpay), amount);

        // send
        vm.prank(payer);
        zkpay.send(asset, amount, onBehalfOf, target, memo);
    }

    function testQueryWithFixedPriceFeed() public {
        vm.startPrank(_owner);

        address asset = address(new MockERC20());
        uint8 tokenDecimals = 18;
        uint64 stalePriceThresholdInSeconds = 1000;
        bytes1 allowedPaymentTypes = AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG;

        FixedPriceFeed fixedPriceFeed = new FixedPriceFeed(8, 1e8);
        address fixedPriceFeedAddress = address(fixedPriceFeed);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(
            asset, allowedPaymentTypes, address(fixedPriceFeed), tokenDecimals, stalePriceThresholdInSeconds
        );

        zkpay.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: allowedPaymentTypes,
                priceFeed: fixedPriceFeedAddress,
                tokenDecimals: tokenDecimals,
                stalePriceThresholdInSeconds: stalePriceThresholdInSeconds
            }),
            DummyData.getOriginAssetPath(asset)
        );

        vm.stopPrank();

        address clientContractAddress = vm.addr(0x3);
        uint248 amount = 1e18;

        // fund payer
        vm.prank(_owner);
        MockERC20(asset).mint(clientContractAddress, amount);

        // approve
        vm.prank(clientContractAddress);
        MockERC20(asset).approve(address(zkpay), amount);

        // query
        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: clientContractAddress,
            callbackGasLimit: 1000000,
            callbackData: "test",
            customLogicContractAddress: address(this)
        });

        // query
        vm.prank(clientContractAddress);
        zkpay.query(address(asset), amount, queryRequest);
    }

    function testFulfillQueryWithFixedPriceFeed() public {
        vm.startPrank(_owner);

        address asset = address(new MockERC20());
        uint8 tokenDecimals = 18;
        uint64 stalePriceThresholdInSeconds = 1000;
        bytes1 allowedPaymentTypes = AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG;

        FixedPriceFeed fixedPriceFeed = new FixedPriceFeed(8, 1e8);
        address fixedPriceFeedAddress = address(fixedPriceFeed);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(
            asset, allowedPaymentTypes, address(fixedPriceFeed), tokenDecimals, stalePriceThresholdInSeconds
        );

        zkpay.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: allowedPaymentTypes,
                priceFeed: fixedPriceFeedAddress,
                tokenDecimals: tokenDecimals,
                stalePriceThresholdInSeconds: stalePriceThresholdInSeconds
            }),
            DummyData.getOriginAssetPath(asset)
        );

        vm.stopPrank();

        address clientContractAddress = address(this);
        uint248 amount = 1e18;

        // fund payer
        vm.prank(_owner);
        MockERC20(asset).mint(clientContractAddress, amount);

        // approve
        vm.prank(clientContractAddress);
        MockERC20(asset).approve(address(zkpay), amount);

        // query
        MockCustomLogic mockedCustomLogic = new MockCustomLogic();

        QueryLogic.QueryRequest memory queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: clientContractAddress,
            callbackGasLimit: 1_000_000,
            callbackData: "test",
            customLogicContractAddress: address(mockedCustomLogic)
        });

        // query
        vm.prank(clientContractAddress);
        bytes32 queryHash = zkpay.query(address(asset), amount, queryRequest);

        // fulfill query
        zkpay.fulfillQuery(queryHash, queryRequest, "results");
    }
}
