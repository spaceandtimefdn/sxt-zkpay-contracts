// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {QueryLogic} from "../src/libraries/QueryLogic.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract QueryCancelationTest is Test {
    ZKPay public _zkpay;
    address public _owner;
    address public _treasury;
    address public _nativeTokenPriceFeed;
    AssetManagement.PaymentAsset public _paymentAssetInstance;
    MockERC20 public _usdc;
    uint248 public _usdcAmount;
    bytes32 public _erc20QueryHash;
    QueryLogic.QueryRequest public _queryRequest;

    event CallbackCalled(bytes32 queryHash, bytes queryResult, bytes callbackData);

    receive() external payable {}

    function setUp() public {
        uint8 nativeTokenDecimals = 18;
        int256 nativeTokenPrice = 1000e8;
        _usdcAmount = 10e6;

        _owner = vm.addr(0x1);
        _treasury = vm.addr(0x2);

        vm.startPrank(_owner);

        // deploy zkpay
        _nativeTokenPriceFeed = address(new MockV3Aggregator(8, nativeTokenPrice));

        address sxt = address(new MockERC20());
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            _owner,
            abi.encodeCall(ZKPay.initialize, (_owner, _treasury, sxt, _nativeTokenPriceFeed, nativeTokenDecimals, 1000))
        );
        _zkpay = ZKPay(zkPayProxyAddress);

        // deploy usdc
        uint8 usdcDecimals = 6;
        _usdc = new MockERC20();
        _usdc.mint(address(this), _usdcAmount);

        // deploy mock price feed
        address mockUsdcPriceFeed = address(new MockV3Aggregator(8, 1e8)); // 1e8 = 1 USD

        // set usdc as a payment asset
        _paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: mockUsdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: 1000
        });
        _zkpay.setPaymentAsset(address(_usdc), _paymentAssetInstance);

        vm.stopPrank();

        address customLogicContractAddress = address(0x101);

        // deploy custom logic contract
        _queryRequest = QueryLogic.QueryRequest({
            query: "test",
            queryParameters: "test",
            timeout: uint64(block.timestamp + 100),
            callbackClientContractAddress: address(this),
            callbackGasLimit: 1_000_000,
            callbackData: "test",
            customLogicContractAddress: customLogicContractAddress
        });

        // allow the zkpay contract to transfer usdc
        _usdc.approve(address(_zkpay), _usdcAmount);

        // query erc20
        _erc20QueryHash = _zkpay.query(address(_usdc), _usdcAmount, _queryRequest);
    }

    function testCancelExpiredQuery() public {
        vm.warp(block.timestamp + 101);

        // erc20 path
        vm.expectEmit(true, true, true, true);
        emit QueryLogic.QueryCanceled(_erc20QueryHash, address(this));
        vm.expectEmit(true, true, true, true);
        emit QueryLogic.PaymentRefunded(_erc20QueryHash, address(_usdc), address(this), _usdcAmount);
        _zkpay.cancelExpiredQuery(_erc20QueryHash, _queryRequest);
    }

    function testCancelExpiredQueryExactBoundary() public {
        // Warp to exactly the timeout timestamp
        vm.warp(_queryRequest.timeout);

        // erc20 path - should succeed at exactly the timeout timestamp
        vm.expectEmit(true, true, true, true);
        emit QueryLogic.QueryCanceled(_erc20QueryHash, address(this));
        vm.expectEmit(true, true, true, true);
        emit QueryLogic.PaymentRefunded(_erc20QueryHash, address(_usdc), address(this), _usdcAmount);
        _zkpay.cancelExpiredQuery(_erc20QueryHash, _queryRequest);
    }

    // test error QueryHasNotExpired
    function testQueryHasNotExpired() public {
        vm.expectRevert(ZKPay.QueryHasNotExpired.selector);
        _zkpay.cancelExpiredQuery(_erc20QueryHash, _queryRequest);
    }
}
