// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DSPay} from "../src/DSPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ZERO_ADDRESS} from "../src/libraries/Constants.sol";
import {DummyData} from "./data/DummyData.sol";
import {MerchantLogic} from "../src/libraries/MerchantLogic.sol";
import {RPC_URL, SXT, USDC, BLOCK_NUMBER, USDT, WETH} from "./data/MainnetConstants.sol";
import {PendingPayment} from "../src/libraries/PendingPayment.sol";
import {IDSPay} from "../src/interfaces/IDSPay.sol";

contract MockCallbackContract {
    address private _merchant;
    uint256 public callCount;
    bytes public lastCallData;
    DSPay.PaymentMetadata public lastPaymentMetadata;
    bool public receivedMetadata;

    error CallbackFailed();

    constructor(address merchant_) {
        _merchant = merchant_;
    }

    function processCallback(uint256 value) external {
        ++callCount;
        lastCallData = abi.encode(value);
    }

    function processCallbackWithMetadata(DSPay.PaymentMetadata calldata metadata, uint256 value) external {
        ++callCount;
        lastCallData = abi.encode(value);
        lastPaymentMetadata = metadata;
        receivedMetadata = true;
    }

    function getLastPaymentMetadata() external view returns (DSPay.PaymentMetadata memory) {
        return lastPaymentMetadata;
    }

    function failingCallback() external pure {
        revert CallbackFailed();
    }
}

contract MockCallbackContractWithMerchantValidation {
    address private _expectedMerchant;
    uint256 public callCount;
    bytes public lastCallData;
    DSPay.PaymentMetadata public lastPaymentMetadata;
    bool public receivedMetadata;

    error InvalidMerchantFromMetadata();

    constructor(address expectedMerchant_) {
        _expectedMerchant = expectedMerchant_;
    }

    function processCallbackWithMetadata(DSPay.PaymentMetadata calldata metadata, uint256 value) external {
        ++callCount;
        lastCallData = abi.encode(value);
        lastPaymentMetadata = metadata;
        receivedMetadata = true;
    }

    function getLastPaymentMetadata() external view returns (DSPay.PaymentMetadata memory) {
        return lastPaymentMetadata;
    }
}

contract PaymentFunctionsTest is Test {
    DSPay public dspay;
    address public admin;
    MockERC20 public usdc;
    uint248 public usdcAmount;
    address public targetMerchant;
    uint64 public itemId;
    address public onBehalfOf;
    bytes public memoBytes;

    function _setupMerchantConfig() internal {
        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
    }

    function _setupCallbackConfig(address contractAddress, bytes4 funcSig) internal {
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: contractAddress,
                funcSig: funcSig,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );
    }

    function _approveUSDC() internal {
        IERC20(USDC).approve(address(dspay), usdcAmount);
    }

    function getOnBehalfOfBytes32() internal view returns (bytes32) {
        return bytes32(uint256(uint160(onBehalfOf)));
    }

    function _setupStandardCallbackTest(address contractAddress, bytes4 funcSig) internal {
        _setupMerchantConfig();
        _setupCallbackConfig(contractAddress, funcSig);
        _approveUSDC();
    }

    function setUp() public {
        vm.createSelectFork(RPC_URL, BLOCK_NUMBER);

        usdcAmount = 10e6;

        admin = vm.addr(0x1);
        onBehalfOf = vm.addr(0x3);
        targetMerchant = vm.addr(0x4);
        itemId = 123;

        memoBytes = abi.encode(itemId);

        vm.startPrank(admin);

        dspay = new DSPay(admin, DummyData.getSwapLogicConfig());

        usdc = MockERC20(USDC);

        deal(USDC, address(this), 100e6);

        address usdcPriceFeed = address(new MockV3Aggregator(8, 1e8));

        dspay.setPaymentAsset(
            USDC,
            AssetManagement.PaymentAsset({
                priceFeed: usdcPriceFeed,
                tokenDecimals: 6,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(USDC)
        );

        vm.stopPrank();
    }

    function createSingleRecipientConfig(address payoutToken, address payoutAddress)
        internal
        pure
        returns (MerchantLogic.MerchantConfig memory)
    {
        address[] memory addresses = new address[](1);
        addresses[0] = payoutAddress;

        uint32[] memory percentages = new uint32[](1);
        percentages[0] = 100 * MerchantLogic.PERCENTAGE_PRECISION;

        return MerchantLogic.MerchantConfig({
            payoutToken: payoutToken,
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });
    }

    function testSendInsufficientPayment() public {
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        IERC20(USDC).approve(address(dspay), usdcAmount);

        vm.prank(targetMerchant);
        dspay.setPaywallItemPrice(bytes32(uint256(itemId)), usdcAmount * 1e12 + 1);

        vm.expectRevert();
        dspay.send(USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)));
    }

    function testSendUSDCPayment() public {
        uint248 usdcAmountTest = 100e6;
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        IERC20(USDC).approve(address(dspay), usdcAmountTest);
        dspay.send(USDC, usdcAmountTest, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0));

        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendToZeroAddress() public {
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        IERC20(USDC).approve(address(dspay), usdcAmount);

        vm.expectRevert();
        dspay.send(USDC, usdcAmount, onBehalfOfBytes32, ZERO_ADDRESS, memoBytes, bytes32(0));
    }

    function testSendWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);

        vm.expectRevert();
        dspay.send(invalidAsset, 100, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(0));
    }

    function testSendWithCallbackHappyPath() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(42);

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.processCallback.selector);

        dspay.sendWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 42);
    }

    function testSendWithCallbackSXTPayment() public {
        uint248 sxtAmount = 100e18;

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.startPrank(admin);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 10e8));
        dspay.setPaymentAsset(
            SXT,
            AssetManagement.PaymentAsset({
                priceFeed: sxtPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(SXT)
        );
        vm.stopPrank();

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(123);

        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        deal(SXT, address(this), sxtAmount);
        IERC20(SXT).approve(address(dspay), sxtAmount);

        dspay.sendWithCallback(
            SXT, sxtAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);

        assertEq(callbackContract.callCount(), 1);
    }

    function testSendWithCallbackWithCallbackData() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(999);

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.processCallback.selector);

        dspay.sendWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 999);
    }

    function testSendWithCallbackExecutorInteraction() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(555);

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.processCallback.selector);

        assertEq(callbackContract.callCount(), 0);

        dspay.sendWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 555);
    }

    function testSendWithCallbackToZeroAddress() public {
        new MockCallbackContract(ZERO_ADDRESS);
        bytes memory callbackData = abi.encode(42);

        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        IERC20(USDC).approve(address(dspay), usdcAmount);

        vm.expectRevert();
        dspay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, ZERO_ADDRESS, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testSendWithCallbackWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(42);

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        dspay.sendWithCallback(
            invalidAsset, 100, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testSendWithCallbackContractCallFailure() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode();

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.failingCallback.selector);

        vm.expectRevert();
        dspay.sendWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testSendWithCallbackItemIdGeneration() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(42);

        bytes4 selector = bytes4(callbackData);
        bytes32 expectedItemId = keccak256(abi.encode(address(callbackContract), selector));

        assertTrue(expectedItemId != bytes32(0));

        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);

        dspay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testFuzzSendWithCallbackAmount(uint248 amount) public {
        vm.assume(amount >= 1000 && amount <= 1000e6);

        deal(USDC, address(this), amount);

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(42);

        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), amount);

        dspay.sendWithCallback(
            USDC, amount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testFuzzSendWithCallbackMemo(bytes calldata memo) public {
        vm.assume(memo.length <= 1000);

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(42);

        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);

        dspay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memo, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testSettleAuthorizedPaymentHappyPath() public {
        address client = address(this);
        uint248 sxtAmount = 100 ether;
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.startPrank(admin);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 10e8));
        dspay.setPaymentAsset(
            SXT,
            AssetManagement.PaymentAsset({
                priceFeed: sxtPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(SXT)
        );
        vm.stopPrank();

        deal(SXT, address(this), sxtAmount);
        IERC20(SXT).approve(address(dspay), sxtAmount);

        dspay.authorize(SXT, sxtAmount, onBehalfOfBytes32, targetMerchant, "test", bytes32(0));

        bytes32 transactionHash = PendingPayment.generateTransactionHash(
            PendingPayment.Transaction({asset: SXT, amount: sxtAmount, from: client, to: targetMerchant}), 1
        );

        // validate emitted event
        vm.expectEmit(true, true, true, false);
        emit IDSPay.AuthorizedPaymentSettled(SXT, sxtAmount, USDC, 0, 0, client, targetMerchant, transactionHash);
        vm.prank(targetMerchant);
        dspay.settleAuthorizedPayment(SXT, sxtAmount, client, transactionHash, 5 ether);

        assertLt(IERC20(SXT).balanceOf(client), sxtAmount);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendPathOverride() public {
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);

        dspay.sendPathOverride(customPath, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0));

        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendPathOverrideToZeroAddress() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        IERC20(USDC).approve(address(dspay), usdcAmount);

        vm.expectRevert(DSPay.MerchantAddressCannotBeZero.selector);
        dspay.sendPathOverride(customPath, usdcAmount, onBehalfOfBytes32, ZERO_ADDRESS, memoBytes, bytes32(0));
    }

    function testSendWithCallbackPathOverride() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(42);
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);

        dspay.sendWithCallbackPathOverride(
            customPath, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendWithCallbackWithPaymentMetadata() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(999);
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallbackWithMetadata.selector,
                includePaymentMetadata: true,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);

        dspay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 999);
        assertTrue(callbackContract.receivedMetadata());

        DSPay.PaymentMetadata memory metadata = callbackContract.getLastPaymentMetadata();
        assertEq(metadata.payoutToken, USDC);
        assertGt(metadata.payoutAmount, 0);
        assertGt(metadata.amountInUSD, 0);
        assertEq(metadata.onBehalfOf, onBehalfOfBytes32);
        assertEq(metadata.sender, address(this));
        assertEq(metadata.itemId, bytes32(uint256(itemId)));
        assertEq(metadata.merchant, targetMerchant);
    }

    function testSendWithCallbackPathOverrideWithPaymentMetadata() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(777);
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallbackWithMetadata.selector,
                includePaymentMetadata: true,
                acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);

        dspay.sendWithCallbackPathOverride(
            customPath, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 777);
        assertTrue(callbackContract.receivedMetadata());

        DSPay.PaymentMetadata memory metadata = callbackContract.getLastPaymentMetadata();
        assertEq(metadata.payoutToken, USDC);
        assertGt(metadata.payoutAmount, 0);
        assertGt(metadata.amountInUSD, 0);
        assertEq(metadata.onBehalfOf, onBehalfOfBytes32);
        assertEq(metadata.sender, address(this));
        assertEq(metadata.itemId, bytes32(uint256(itemId)));
        assertEq(metadata.merchant, targetMerchant);
    }

    function testSendWithCallbackPathOverrideToZeroAddress() public {
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        IERC20(USDC).approve(address(dspay), usdcAmount);

        vm.expectRevert(MerchantLogic.ItemIdCallbackNotConfigured.selector);
        dspay.sendWithCallbackPathOverride(
            customPath, usdcAmount, onBehalfOfBytes32, ZERO_ADDRESS, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testSettleAuthorizedPaymentPathOverride() public {
        address client = address(this);
        uint248 sxtAmount = 100 ether;
        bytes32 onBehalfOfBytes32 = getOnBehalfOfBytes32();
        bytes memory customPath =
            abi.encodePacked(SXT, uint24(3000), USDT, uint24(100), USDC, uint24(500), WETH, uint24(3000), USDT);

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        vm.startPrank(admin);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 10e8));
        dspay.setPaymentAsset(
            SXT,
            AssetManagement.PaymentAsset({
                priceFeed: sxtPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(SXT)
        );
        vm.stopPrank();

        deal(SXT, address(this), sxtAmount);
        IERC20(SXT).approve(address(dspay), sxtAmount);

        dspay.authorize(SXT, sxtAmount, onBehalfOfBytes32, targetMerchant, "test", bytes32(0));

        bytes32 transactionHash = PendingPayment.generateTransactionHash(
            PendingPayment.Transaction({asset: SXT, amount: sxtAmount, from: client, to: targetMerchant}), 1
        );

        vm.expectEmit(true, true, true, false);
        emit IDSPay.AuthorizedPaymentSettled(SXT, sxtAmount, USDC, 0, 0, client, targetMerchant, transactionHash);
        vm.prank(targetMerchant);
        dspay.settleAuthorizedPaymentPathOverride(customPath, sxtAmount, client, transactionHash, 5 ether);

        assertLt(IERC20(SXT).balanceOf(client), sxtAmount);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendWithCallbackRejectsAuthorizeOnlyMethod() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        _setupMerchantConfig();
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );
        IERC20(USDC).approve(address(dspay), usdcAmount);
        vm.expectRevert(MerchantLogic.UnsupportedPaymentMethod.selector);
        dspay.sendWithCallback(
            USDC,
            usdcAmount,
            getOnBehalfOfBytes32(),
            targetMerchant,
            memoBytes,
            bytes32(uint256(itemId)),
            abi.encode(123)
        );
    }

    function testAuthorizeWithCallbackRejectsSendOnlyMethod() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(123);
        bytes4 selector = MockCallbackContract.processCallback.selector;
        bytes32 generatedItemId = keccak256(abi.encode(address(callbackContract), selector));

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            generatedItemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD
            })
        );

        vm.expectRevert(MerchantLogic.UnsupportedPaymentMethod.selector);
        dspay.authorizeWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, generatedItemId, callbackData
        );
    }

    function testSendWithCallbackAcceptsSendMethod() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        _setupMerchantConfig();
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.SEND_METHOD
            })
        );
        IERC20(USDC).approve(address(dspay), usdcAmount);
        dspay.sendWithCallback(
            USDC,
            usdcAmount,
            getOnBehalfOfBytes32(),
            targetMerchant,
            memoBytes,
            bytes32(uint256(itemId)),
            abi.encode(123)
        );
        assertEq(callbackContract.callCount(), 1);
    }

    function testAuthorizeWithCallbackAcceptsAuthorizeMethod() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(123);
        bytes4 selector = MockCallbackContract.processCallback.selector;
        bytes32 generatedItemId = keccak256(abi.encode(address(callbackContract), selector));

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            generatedItemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);
        dspay.authorizeWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, generatedItemId, callbackData
        );
        assertEq(callbackContract.callCount(), 1);
    }

    function testAuthorizeWithCallbackWorksWithoutConfig() public {
        bytes memory callbackData = abi.encode(123);

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);
        vm.expectRevert(MerchantLogic.ItemIdCallbackNotConfigured.selector);
        dspay.authorizeWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testAuthorizeWithCallbackWithMetadata() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(456);
        bytes4 selector = MockCallbackContract.processCallbackWithMetadata.selector;
        bytes32 generatedItemId = keccak256(abi.encode(address(callbackContract), selector));

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            generatedItemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: selector,
                includePaymentMetadata: true,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);
        dspay.authorizeWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, generatedItemId, callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 456);
        assertTrue(callbackContract.receivedMetadata());

        DSPay.PaymentMetadata memory metadata = callbackContract.getLastPaymentMetadata();
        assertEq(metadata.payoutToken, USDC);
        assertEq(metadata.payoutAmount, 0);
        assertGt(metadata.amountInUSD, 0);
        assertEq(metadata.onBehalfOf, getOnBehalfOfBytes32());
        assertEq(metadata.sender, address(this));
        assertEq(metadata.itemId, generatedItemId);
        assertEq(metadata.merchant, targetMerchant);
    }

    function testAuthorizeWithCallbackWithoutMetadata() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(789);
        bytes4 selector = MockCallbackContract.processCallback.selector;
        bytes32 generatedItemId = keccak256(abi.encode(address(callbackContract), selector));

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            generatedItemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);
        dspay.authorizeWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, generatedItemId, callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 789);
        assertFalse(callbackContract.receivedMetadata());
    }

    function testSendWithCallbackMerchantValidationViaMetadata() public {
        MockCallbackContractWithMerchantValidation callbackContract =
            new MockCallbackContractWithMerchantValidation(targetMerchant);
        bytes memory callbackData = abi.encode(123);

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContractWithMerchantValidation.processCallbackWithMetadata.selector,
                includePaymentMetadata: true,
                acceptedMethods: MerchantLogic.SEND_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);
        dspay.sendWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertTrue(callbackContract.receivedMetadata());
        assertEq(callbackContract.getLastPaymentMetadata().merchant, targetMerchant);
    }

    function testCallbackContractCanValidateViaBothMethods() public {
        MockCallbackContractWithMerchantValidation callbackContract =
            new MockCallbackContractWithMerchantValidation(targetMerchant);
        bytes memory callbackData = abi.encode(456);

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContractWithMerchantValidation.processCallbackWithMetadata.selector,
                includePaymentMetadata: true,
                acceptedMethods: MerchantLogic.SEND_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);
        dspay.sendWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertTrue(callbackContract.receivedMetadata());
        assertEq(callbackContract.getLastPaymentMetadata().merchant, targetMerchant);
    }

    function testAuthorizeWithCallbackMerchantValidationViaMetadata() public {
        MockCallbackContractWithMerchantValidation callbackContract =
            new MockCallbackContractWithMerchantValidation(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(
            MockCallbackContractWithMerchantValidation.processCallbackWithMetadata.selector, uint256(456)
        );
        bytes4 selector = MockCallbackContractWithMerchantValidation.processCallbackWithMetadata.selector;
        bytes32 generatedItemId = keccak256(abi.encode(address(callbackContract), selector));

        vm.prank(targetMerchant);
        dspay.setMerchantConfig(
            createSingleRecipientConfig(USDC, targetMerchant), DummyData.getDestinationAssetPath(USDC)
        );
        vm.prank(targetMerchant);
        dspay.setItemIdCallbackConfig(
            generatedItemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: selector,
                includePaymentMetadata: true,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        IERC20(USDC).approve(address(dspay), usdcAmount);
        dspay.authorizeWithCallback(
            USDC, usdcAmount, getOnBehalfOfBytes32(), targetMerchant, memoBytes, generatedItemId, callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertTrue(callbackContract.receivedMetadata());
        assertEq(callbackContract.getLastPaymentMetadata().merchant, targetMerchant);
    }
}
