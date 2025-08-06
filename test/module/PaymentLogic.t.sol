// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentLogic} from "../../src/module/PaymentLogic.sol";
import {PayWallLogic} from "../../src/libraries/PayWallLogic.sol";
import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../../src/libraries/Constants.sol";
import {ZKPay} from "../../src/ZKPay.sol";
import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {SwapLogic} from "../../src/libraries/SwapLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {RPC_URL, ROUTER, USDT, SXT, USDC, BLOCK_NUMBER} from "../data/MainnetConstants.sol";

contract PaymentLogicTestWrapper {
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;

    PayWallLogic.PayWallLogicStorage internal _paywallStorage;

    function calculateProtocolFee(address asset, uint248 amount, address sxt)
        external
        pure
        returns (uint248 protocolFeeAmount, uint248 remainingAmount)
    {
        return PaymentLogic._calculateProtocolFee(asset, amount, sxt);
    }

    function setItemPrice(address merchant, bytes32 itemId, uint248 price) external {
        _paywallStorage.setItemPrice(merchant, itemId, price);
    }

    function validateItemPrice(address merchant, bytes32 itemId, uint248 amountInUSD) external view {
        PaymentLogic._validateItemPrice(_paywallStorage, merchant, itemId, amountInUSD);
    }
}

contract PaymentLogicTest is Test {
    PaymentLogicTestWrapper internal _wrapper;
    address internal constant SXT_TOKEN = address(0x1);
    address internal constant OTHER_TOKEN = address(0x2);
    address internal constant MERCHANT = address(0x3);
    bytes32 internal constant ITEM_ID = keccak256("test_item");

    function setUp() public {
        _wrapper = new PaymentLogicTestWrapper();
    }

    function testCalculateProtocolFeeWithSXTToken() public view {
        uint248 amount = 1000 ether;

        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            _wrapper.calculateProtocolFee(SXT_TOKEN, amount, SXT_TOKEN);

        assertEq(protocolFeeAmount, 0);
        assertEq(remainingAmount, amount);
    }

    function testCalculateProtocolFeeWithOtherToken() public view {
        uint248 amount = 1000 ether;
        uint248 expectedProtocolFee = uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        uint248 expectedRemainingAmount = amount - expectedProtocolFee;

        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            _wrapper.calculateProtocolFee(OTHER_TOKEN, amount, SXT_TOKEN);

        assertEq(protocolFeeAmount, expectedProtocolFee);
        assertEq(remainingAmount, expectedRemainingAmount);
    }

    function testCalculateProtocolFeeZeroAmount() public view {
        uint248 amount = 0;

        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            _wrapper.calculateProtocolFee(OTHER_TOKEN, amount, SXT_TOKEN);

        assertEq(protocolFeeAmount, 0);
        assertEq(remainingAmount, 0);
    }

    function testFuzzCalculateProtocolFee(address asset, uint248 amount) public view {
        (uint248 protocolFeeAmount, uint248 remainingAmount) = _wrapper.calculateProtocolFee(asset, amount, SXT_TOKEN);

        if (asset == SXT_TOKEN) {
            assertEq(protocolFeeAmount, 0);
            assertEq(remainingAmount, amount);
        } else {
            uint248 expectedProtocolFee = uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
            assertEq(protocolFeeAmount, expectedProtocolFee);
            assertEq(remainingAmount, amount - expectedProtocolFee);
        }

        assertEq(protocolFeeAmount + remainingAmount, amount);
    }

    function testCalculateProtocolFeeWithSpecificValues() public view {
        uint248[] memory testAmounts = new uint248[](8);
        testAmounts[0] = 1 ether;
        testAmounts[1] = 100 ether;
        testAmounts[2] = 10000 ether;
        testAmounts[3] = 1000000 ether;
        testAmounts[4] = 1;
        testAmounts[5] = 1e3;
        testAmounts[6] = 1e6;
        testAmounts[7] = 1e9;

        uint256 length = testAmounts.length;
        for (uint256 i = 0; i < length; ++i) {
            uint248 amount = testAmounts[i];
            uint248 expectedProtocolFee = uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);

            (uint248 protocolFeeAmount, uint248 remainingAmount) =
                _wrapper.calculateProtocolFee(OTHER_TOKEN, amount, SXT_TOKEN);

            assertEq(protocolFeeAmount, expectedProtocolFee);
            assertEq(remainingAmount, amount - expectedProtocolFee);
            assertEq(protocolFeeAmount + remainingAmount, amount);
        }
    }

    function testValidateItemPriceSuccess() public {
        uint248 itemPrice = 100 ether;
        uint248 paymentAmount = 150 ether;

        _wrapper.setItemPrice(MERCHANT, ITEM_ID, itemPrice);
        _wrapper.validateItemPrice(MERCHANT, ITEM_ID, paymentAmount);
    }

    function testValidateItemPriceExactAmount() public {
        uint248 itemPrice = 100 ether;
        uint248 paymentAmount = 100 ether;

        _wrapper.setItemPrice(MERCHANT, ITEM_ID, itemPrice);
        _wrapper.validateItemPrice(MERCHANT, ITEM_ID, paymentAmount);
    }

    function testValidateItemPriceInsufficientPayment() public {
        uint248 itemPrice = 100 ether;
        uint248 paymentAmount = 99 ether;

        _wrapper.setItemPrice(MERCHANT, ITEM_ID, itemPrice);

        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        _wrapper.validateItemPrice(MERCHANT, ITEM_ID, paymentAmount);
    }

    function testValidateItemPriceZeroItemPrice() public {
        uint248 itemPrice = 0;
        uint248 paymentAmount = 1 ether;

        _wrapper.setItemPrice(MERCHANT, ITEM_ID, itemPrice);
        _wrapper.validateItemPrice(MERCHANT, ITEM_ID, paymentAmount);
    }

    function testValidateItemPriceZeroPaymentAmount() public {
        uint248 itemPrice = 1 ether;
        uint248 paymentAmount = 0;

        _wrapper.setItemPrice(MERCHANT, ITEM_ID, itemPrice);

        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        _wrapper.validateItemPrice(MERCHANT, ITEM_ID, paymentAmount);
    }

    function testFuzzValidateItemPrice(address merchant, bytes32 itemId, uint248 itemPrice, uint248 paymentAmount)
        public
    {
        _wrapper.setItemPrice(merchant, itemId, itemPrice);

        if (paymentAmount >= itemPrice) {
            _wrapper.validateItemPrice(merchant, itemId, paymentAmount);
        } else {
            vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
            _wrapper.validateItemPrice(merchant, itemId, paymentAmount);
        }
    }

    function testValidateItemPriceMultipleMerchants() public {
        address merchant1 = address(0x4);
        address merchant2 = address(0x5);
        bytes32 itemId1 = keccak256("item1");
        bytes32 itemId2 = keccak256("item2");
        uint248 price1 = 50 ether;
        uint248 price2 = 75 ether;

        _wrapper.setItemPrice(merchant1, itemId1, price1);
        _wrapper.setItemPrice(merchant2, itemId2, price2);

        _wrapper.validateItemPrice(merchant1, itemId1, price1);
        _wrapper.validateItemPrice(merchant2, itemId2, price2);

        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        _wrapper.validateItemPrice(merchant1, itemId1, price1 - 1);

        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        _wrapper.validateItemPrice(merchant2, itemId2, price2 - 1);
    }
}

contract PaymentLogicProcessPaymentWrapper {
    using PaymentLogic for ZKPay.ZKPayStorage;
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;

    ZKPay.ZKPayStorage internal zkPayStorage;

    address public constant TREASURY = address(0x9999);
    address public constant MERCHANT = address(0x8888);

    constructor() {
        zkPayStorage.sxt = SXT;
        zkPayStorage.treasury = TREASURY;

        zkPayStorage.swapLogicStorage.swapLogicConfig =
            SwapLogic.SwapLogicConfig({router: ROUTER, usdt: USDT, defaultTargetAssetPath: abi.encodePacked(USDT)});

        zkPayStorage.swapLogicStorage.assetSwapPaths.sourceAssetPaths[SXT] =
            abi.encodePacked(SXT, bytes3(uint24(3000)), USDT);
        zkPayStorage.swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[MERCHANT] =
            abi.encodePacked(USDT, bytes3(uint24(3000)), USDC);

        MockV3Aggregator sxtPriceFeed = new MockV3Aggregator(8, 1000000000);
        AssetManagement.PaymentAsset memory sxtAsset = AssetManagement.PaymentAsset({
            priceFeed: address(sxtPriceFeed),
            tokenDecimals: 18,
            stalePriceThresholdInSeconds: 3600
        });
        AssetManagement.set(zkPayStorage.assets, SXT, sxtAsset);
    }

    function processPayment(PaymentLogic.ProcessPaymentParams calldata params)
        external
        returns (
            address payoutToken,
            uint248 receivedProtocolFeeAmount,
            uint248 amountInUSD,
            uint256 recievedPayoutAmount
        )
    {
        return PaymentLogic.processPayment(zkPayStorage, params);
    }

    function setItemPrice(address merchant, bytes32 itemId, uint248 price) external {
        zkPayStorage.paywallLogicStorage.setItemPrice(merchant, itemId, price);
    }
}

contract PaymentLogicProcessPaymentTest is Test {
    using PaymentLogic for ZKPay.ZKPayStorage;
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using SwapLogic for SwapLogic.SwapLogicStorage;

    PaymentLogicProcessPaymentWrapper internal wrapper;

    address public constant TREASURY = address(0x9999);
    address public constant MERCHANT = address(0x8888);

    function setUp() public {
        vm.createSelectFork(RPC_URL, BLOCK_NUMBER);
        wrapper = new PaymentLogicProcessPaymentWrapper();
    }

    function testProcessPaymentSXTToUSDC() public {
        uint248 amount = 100 ether;
        bytes32 itemId = bytes32("test_item");

        deal(SXT, address(this), amount);
        IERC20(SXT).approve(address(wrapper), amount);

        PaymentLogic.ProcessPaymentParams memory params =
            PaymentLogic.ProcessPaymentParams({asset: SXT, amount: amount, merchant: MERCHANT, itemId: itemId});

        try wrapper.processPayment(params) returns (
            address payoutToken, uint248 receivedProtocolFeeAmount, uint248 amountInUSD, uint256 recievedPayoutAmount
        ) {
            assertEq(payoutToken, USDC);
            assertEq(receivedProtocolFeeAmount, 0);
            assertGt(amountInUSD, 0);
            assertGt(recievedPayoutAmount, 0);
            assertEq(IERC20(USDC).balanceOf(MERCHANT), recievedPayoutAmount);
        } catch (bytes memory reason) {
            emit log("Failed with reason:");
            emit log_bytes(reason);
            // solhint-disable-next-line gas-custom-errors
            revert("processPayment failed");
        }
    }

    function testProcessPaymentInsufficientPaymentReverts() public {
        uint248 amount = 1 ether;
        bytes32 itemId = bytes32("expensive_item");
        uint248 itemPrice = 10000 ether;

        wrapper.setItemPrice(MERCHANT, itemId, itemPrice);

        deal(SXT, address(this), amount);
        IERC20(SXT).approve(address(wrapper), amount);

        PaymentLogic.ProcessPaymentParams memory params =
            PaymentLogic.ProcessPaymentParams({asset: SXT, amount: amount, merchant: MERCHANT, itemId: itemId});

        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        wrapper.processPayment(params);
    }

    function testProcessPaymentUnsupportedAssetReverts() public {
        uint248 amount = 100 ether;
        bytes32 itemId = bytes32("test_item");
        address unsupportedAsset = address(0xDEAD);

        PaymentLogic.ProcessPaymentParams memory params = PaymentLogic.ProcessPaymentParams({
            asset: unsupportedAsset,
            amount: amount,
            merchant: MERCHANT,
            itemId: itemId
        });

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        wrapper.processPayment(params);
    }
}
