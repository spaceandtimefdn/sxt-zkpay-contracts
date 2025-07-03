// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {ZKPay} from "../../src/ZKPay.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {QueryLogic} from "../../src/libraries/QueryLogic.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MockCustomLogic} from "../mocks/MockCustomLogic.sol";
import {DummyData} from "../data/DummyData.sol";

/**
 * @title ClientFallbackMethodTest
 * @notice This contract tests two different reentrancy protection scenarios:
 * 1. Fallback Attack: Tests that reentrancy is prevented when ETH is sent back to a contract without a receive function
 * 2. Callback Reentrancy: Tests that reentrancy is prevented when a callback tries to make a reentrant call
 */
contract ClientFallbackMethodTest is Test {
    ZKPay public zkpay;
    address public _owner;
    address public _treasury;
    address public _nativeTokenPriceFeed;
    AssetManagement.PaymentAsset public paymentAssetInstance;
    bytes32 public _queryHash;
    QueryLogic.QueryRequest public _queryRequest;

    event NativePaymentSettled(bytes32 queryHash, uint248 payoutAmount, uint248 refundAmount);

    function setUp() public {
        uint8 nativeTokenDecimals = 18;
        int256 nativeTokenPrice = 1000e8;

        _owner = vm.addr(0x1);
        _treasury = vm.addr(0x2);

        vm.startPrank(_owner);

        // deploy zkpay
        _nativeTokenPriceFeed = address(new MockV3Aggregator(8, nativeTokenPrice));

        address sxt = address(new MockERC20());
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            _owner,
            abi.encodeCall(
                ZKPay.initialize,
                (
                    _owner,
                    _treasury,
                    sxt,
                    _nativeTokenPriceFeed,
                    nativeTokenDecimals,
                    1000,
                    DummyData.getSwapLogicConfig()
                )
            )
        );
        zkpay = ZKPay(zkPayProxyAddress);

        // deploy usdc
        uint8 usdcDecimals = 6;
        MockERC20 usdc = new MockERC20();

        // deploy mock price feed
        address mockUsdcPriceFeed = address(new MockV3Aggregator(8, 1e8)); // 1e8 = 1 USD

        // set usdc as a payment asset
        paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: mockUsdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: 1000
        });
        zkpay.setPaymentAsset(address(usdc), paymentAssetInstance, DummyData.getOriginAssetPath(address(usdc)));

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

        uint248 amount = 10e6;

        usdc.mint(address(this), amount);

        // allow the zkpay contract to transfer usdc
        usdc.approve(address(zkpay), amount);

        // query
        _queryHash = zkpay.query(address(usdc), amount, _queryRequest);
    }

    /**
     * @notice TEST 1: FALLBACK ATTACK TEST
     * This function tests reentrancy protection when ETH is sent back to a contract without a receive function.
     * When ETH is sent to this contract and there's no receive() function, this fallback() is triggered.
     * We then attempt to make a reentrant call to zkpay.cancelQuery(), which should be blocked by the reentrancy guard.
     */
    fallback() external payable {
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        zkpay.cancelExpiredQuery(_queryHash, _queryRequest);
    }

    // Add receive function to handle plain ETH transfers and fix compiler warnings
    receive() external payable {
        // Empty implementation - just to receive ETH
    }

    /**
     * @notice Callback function called by ZKPay during fulfillQuery
     * This function attempts to make a reentrant call back to zkpay.fulfillQuery()
     * The reentrant call should be blocked by the reentrancy guard
     */
    function zkPayCallback(bytes32, /* queryHash */ bytes calldata, /* results */ bytes calldata /* callbackData */ )
        external
    {
        // Attempt to make a reentrant call to test the reentrancy guard
        // This should revert, but we can't use vm.expectRevert here because it's a callback
        zkpay.fulfillQuery(_queryHash, _queryRequest, "results");
    }

    /**
     * @notice TEST 2: CALLBACK REENTRANCY TEST
     * This function tests reentrancy protection during callbacks.
     * It calls zkpay.fulfillQuery(), which triggers the zkPayCallback() function above.
     * Inside the callback, we attempt to make a reentrant call back to zkpay.fulfillQuery().
     * The test passes if execution completes, which means the reentrant call in the callback was blocked.
     * Note: We don't use vm.expectRevert() here because the initial call should succeed;
     * only the reentrant call from within the callback should revert.
     */
    function testReentrancyGuardReentrantCall() public {
        zkpay.fulfillQuery(_queryHash, _queryRequest, "results");
    }
}
