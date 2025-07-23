// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";
import {Setup} from "./Setup.sol";

// Mock contract that simulates incomplete round data from Chainlink price feed
contract MockIncompleteRoundDataAggregator {
    // This function returns values that should fail validation:
    // - answeredInRound < roundId (incomplete round)
    // - startedAt = 0 (round not properly initialized)
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        uint80 roundId = 10;
        int256 answer = 100; // Valid price
        uint256 startedAt = 0; // Invalid: round not initialized
        uint256 updatedAt = block.timestamp; // Recent timestamp
        uint80 answeredInRound = 5; // Invalid: answeredInRound < roundId

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    // Required for isContract check
    function dummy() external pure returns (bool) {
        return true;
    }
}

// Mock contract that returns zero price
contract MockZeroPriceAggregator {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        uint80 roundId = 10;
        int256 answer = 0; // Zero price - should fail validation
        uint256 startedAt = 1; // Valid: round initialized
        uint256 updatedAt = block.timestamp; // Recent timestamp
        uint80 answeredInRound = 10; // Valid: answeredInRound == roundId

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    // Required for isContract check
    function dummy() external pure returns (bool) {
        return true;
    }
}

contract AssetManagementTestWrapper {
    mapping(address asset => AssetManagement.PaymentAsset) internal _assets;
    address internal _usdcAddress;

    constructor() {
        _usdcAddress = address(new MockERC20());

        Setup.setupAssets(_assets, _usdcAddress);
    }

    function validatePriceFeed(AssetManagement.PaymentAsset calldata paymentAsset) external view {
        AssetManagement._validatePriceFeed(paymentAsset);
    }

    function getPrice(address assetAddress) external view returns (uint256 safePrice, uint8 priceFeedDecimals) {
        return AssetManagement._getPrice(_assets, assetAddress);
    }

    function setPaymentAsset(address asset, AssetManagement.PaymentAsset calldata paymentAsset) external {
        AssetManagement.set(_assets, asset, paymentAsset);
    }

    function getPaymentAsset(address asset) external view returns (AssetManagement.PaymentAsset memory) {
        return _assets[asset];
    }

    function removeAsset(address asset) external {
        AssetManagement.remove(_assets, asset);
    }

    function isSupported(address asset) external view returns (bool) {
        return AssetManagement.isSupported(_assets, asset);
    }

    function convertToUsd(address asset, uint248 amount) external view returns (uint248) {
        return AssetManagement.convertToUsd(_assets, asset, amount);
    }

    function escrowPayment(address asset, uint248 amount) external returns (uint248, uint248) {
        return AssetManagement.escrowPayment(_assets, asset, amount);
    }

    function convertUsdToToken(address asset, uint248 usdValue) external view returns (uint248) {
        return AssetManagement.convertUsdToToken(_assets, asset, usdValue);
    }
}

contract AssetManagementTest is Test {
    AssetManagementTestWrapper internal _wrapper;

    function setUp() public {
        _wrapper = new AssetManagementTestWrapper();
    }

    function testFuzzSet(address asset, uint8 tokenDecimals, uint64 stalePriceThresholdInSeconds) public {
        address priceFeed = address(new MockV3Aggregator(8, 100));

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(asset, priceFeed, tokenDecimals, stalePriceThresholdInSeconds);

        _wrapper.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                priceFeed: priceFeed,
                tokenDecimals: tokenDecimals,
                stalePriceThresholdInSeconds: stalePriceThresholdInSeconds
            })
        );

        AssetManagement.PaymentAsset memory paymentAsset = _wrapper.getPaymentAsset(asset);
        assertEq(paymentAsset.priceFeed, priceFeed);
        assertEq(paymentAsset.tokenDecimals, tokenDecimals);
        assertEq(paymentAsset.stalePriceThresholdInSeconds, stalePriceThresholdInSeconds);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSetPaymentAssetWithInvalidPriceFeed() public {
        vm.expectRevert(AssetManagement.InvalidPriceFeed.selector);
        _wrapper.setPaymentAsset(
            address(0x1),
            AssetManagement.PaymentAsset({priceFeed: address(0x1), tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );
    }

    function testRemoveAsset() public {
        address priceFeed = address(new MockV3Aggregator(8, 100));

        _wrapper.setPaymentAsset(
            address(0x4),
            AssetManagement.PaymentAsset({priceFeed: priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetRemoved(address(0x4));

        _wrapper.removeAsset(address(0x4));

        assertEq(_wrapper.getPaymentAsset(address(0x4)).priceFeed, address(0));
    }

    function testIsSupported() public {
        assertEq(_wrapper.isSupported(address(0x1)), false);

        address priceFeed = address(new MockV3Aggregator(8, 100));
        _wrapper.setPaymentAsset(
            address(0x1),
            AssetManagement.PaymentAsset({priceFeed: priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );

        assertEq(_wrapper.isSupported(address(0x1)), true);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testInvalidPriceFeedWhenZeroAddress() public {
        vm.expectRevert(AssetManagement.InvalidPriceFeed.selector);
        _wrapper.validatePriceFeed(
            AssetManagement.PaymentAsset({priceFeed: ZERO_ADDRESS, tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );
    }

    function testInvalidPriceFeedWhenZeroAnswer() public {
        address priceFeed = address(new MockV3Aggregator(8, 100));
        MockV3Aggregator(priceFeed).updateAnswer(0);
        vm.expectRevert(AssetManagement.InvalidPriceFeedData.selector);
        _wrapper.validatePriceFeed(
            AssetManagement.PaymentAsset({priceFeed: priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );
    }

    function testCallLatestRoundData() public {
        address priceFeed = address(new MockV3Aggregator(8, 100));
        (, int256 answer,,,) = AggregatorV3Interface(priceFeed).latestRoundData();

        assert(answer > 0);
    }

    function testInvalidPriceFeedWhenStale() public {
        MockV3Aggregator priceFeed2 = new MockV3Aggregator(100, 18);
        vm.warp(block.timestamp + 10_000);
        vm.expectRevert(AssetManagement.StalePriceFeedData.selector);
        _wrapper.validatePriceFeed(
            AssetManagement.PaymentAsset({
                priceFeed: address(priceFeed2),
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );
    }

    function testInvalidPriceFeedWhenNegativePrice() public {
        address priceFeed = address(new MockV3Aggregator(8, 100));
        MockV3Aggregator(priceFeed).updateAnswer(-1);
        vm.expectRevert(AssetManagement.InvalidPriceFeedData.selector);
        _wrapper.validatePriceFeed(
            AssetManagement.PaymentAsset({priceFeed: priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );
    }

    function testGetPriceZeroAnswer() public {
        // Create a custom mock that returns zero price
        MockZeroPriceAggregator mockZeroAggregator = new MockZeroPriceAggregator();

        vm.expectRevert(AssetManagement.InvalidPriceFeedData.selector);
        _wrapper.validatePriceFeed(
            AssetManagement.PaymentAsset({
                priceFeed: address(mockZeroAggregator),
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );
    }

    function testInvalidPriceFeedIncompleteRoundData() public {
        // Create a custom mock that can simulate incomplete round data
        MockIncompleteRoundDataAggregator mockIncompleteAggregator = new MockIncompleteRoundDataAggregator();

        vm.expectRevert(AssetManagement.InvalidPriceFeedData.selector);
        _wrapper.validatePriceFeed(
            AssetManagement.PaymentAsset({
                priceFeed: address(mockIncompleteAggregator),
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );
    }

    function testGetPriceStalePriceFeedData() public {
        MockV3Aggregator priceFeed2 = new MockV3Aggregator(100, 18);
        address asset = address(0x0123);

        _wrapper.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                priceFeed: address(priceFeed2),
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );

        priceFeed2.updateAnswer(0);
        vm.expectRevert(AssetManagement.InvalidPriceFeedData.selector);
        _wrapper.getPrice(asset);
    }

    function testGetPriceWhenStalePriceFeed() public {
        MockV3Aggregator priceFeed2 = new MockV3Aggregator(100, 18);
        address asset = address(0x0123);

        _wrapper.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                priceFeed: address(priceFeed2),
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );

        vm.warp(block.timestamp + 10_000);
        vm.expectRevert(AssetManagement.StalePriceFeedData.selector);
        _wrapper.getPrice(asset);
    }

    function testConvertToUsd() public {
        address priceFeed = address(new MockV3Aggregator(8, 1e8)); // 1e8 = 1 USD

        _wrapper.setPaymentAsset(
            address(0x1),
            AssetManagement.PaymentAsset({priceFeed: priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );

        uint248 amount = 1e18;
        uint248 usdValue = _wrapper.convertToUsd(address(0x1), amount);
        assertEq(usdValue, amount);
    }

    function testConvertUsdToToken() public {
        address priceFeed = address(new MockV3Aggregator(8, 1e8)); // 1e8 = 1 USD

        _wrapper.setPaymentAsset(
            address(0x1),
            AssetManagement.PaymentAsset({priceFeed: priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 100})
        );

        uint248 usdValue = 1e18; // 1 USD in 18 decimals
        uint248 tokenAmount = _wrapper.convertUsdToToken(address(0x1), usdValue);
        assertEq(tokenAmount, 1e18); // Should be 1 token with 18 decimals
    }

    function testMockContractDummyFunctions() public {
        // Test the dummy functions in the mock contracts
        MockZeroPriceAggregator mockZero = new MockZeroPriceAggregator();
        assertTrue(mockZero.dummy());

        MockIncompleteRoundDataAggregator mockIncomplete = new MockIncompleteRoundDataAggregator();
        assertTrue(mockIncomplete.dummy());
    }

    function testEscrowPayment() public {
        MockERC20 mockToken = new MockERC20();
        address tokenAddress = address(mockToken);
        address priceFeed = address(new MockV3Aggregator(8, 1e8)); // 1 USD

        _wrapper.setPaymentAsset(
            tokenAddress,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG,
                priceFeed: priceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );

        uint248 escrowAmount = 1000 ether;
        mockToken.mint(address(this), escrowAmount);

        mockToken.approve(address(_wrapper), escrowAmount);

        uint256 initialContractBalance = mockToken.balanceOf(address(_wrapper));
        uint256 initialUserBalance = mockToken.balanceOf(address(this));

        (uint248 actualAmountReceived,) = _wrapper.escrowPayment(tokenAddress, escrowAmount);

        uint256 finalContractBalance = mockToken.balanceOf(address(_wrapper));
        uint256 finalUserBalance = mockToken.balanceOf(address(this));

        assertEq(actualAmountReceived, escrowAmount);
        assertEq(finalContractBalance, initialContractBalance + escrowAmount);
        assertEq(finalUserBalance, initialUserBalance - escrowAmount);
    }

    function testEscrowPaymentWithDifferentAmounts() public {
        MockERC20 mockToken = new MockERC20();
        address tokenAddress = address(mockToken);
        address priceFeed = address(new MockV3Aggregator(8, 1e8)); // 1 USD

        _wrapper.setPaymentAsset(
            tokenAddress,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG,
                priceFeed: priceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );

        uint248[] memory testAmounts = new uint248[](3);
        testAmounts[0] = 1 ether;
        testAmounts[1] = 500 ether;
        testAmounts[2] = 1000000 ether;

        uint256 length = testAmounts.length;

        for (uint256 i = 0; i < length; ++i) {
            uint248 escrowAmount = testAmounts[i];

            mockToken.mint(address(this), escrowAmount);
            mockToken.approve(address(_wrapper), escrowAmount);

            uint256 initialContractBalance = mockToken.balanceOf(address(_wrapper));

            (uint248 actualAmountReceived,) = _wrapper.escrowPayment(tokenAddress, escrowAmount);

            uint256 finalContractBalance = mockToken.balanceOf(address(_wrapper));

            assertEq(actualAmountReceived, escrowAmount);
            assertEq(finalContractBalance, initialContractBalance + escrowAmount);
        }
    }

    function testEscrowPaymentUnsupportedAsset() public {
        address unsupportedAsset = address(0x9999);
        uint248 escrowAmount = 1000e18;

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        _wrapper.escrowPayment(unsupportedAsset, escrowAmount);
    }

    function testEscrowPaymentZeroAmount() public {
        MockERC20 mockToken = new MockERC20();
        address tokenAddress = address(mockToken);
        address priceFeed = address(new MockV3Aggregator(8, 1e8)); // 1 USD

        _wrapper.setPaymentAsset(
            tokenAddress,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG,
                priceFeed: priceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 100
            })
        );

        mockToken.mint(address(this), 1000e18);
        mockToken.approve(address(_wrapper), 1000e18);

        (uint248 actualAmountReceived,) = _wrapper.escrowPayment(tokenAddress, 0);

        assertEq(actualAmountReceived, 0);
    }
}
