// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION, ZERO_ADDRESS} from "../src/libraries/Constants.sol";
import {DummyData} from "./data/DummyData.sol";
import {IMerchantCallback} from "../src/interfaces/IMerchantCallback.sol";
import {MerchantLogic} from "../src/libraries/MerchantLogic.sol";
import {RPC_URL, SXT, USDC, BLOCK_NUMBER} from "./data/MainnetConstants.sol";
import {EscrowPayment} from "../src/libraries/EscrowPayment.sol";
import {IZKPay} from "../src/interfaces/IZKPay.sol";

contract MockCallbackContract is IMerchantCallback {
    address private _merchant;
    uint256 public callCount;
    bytes public lastCallData;
    ZKPay.PaymentMetadata public lastPaymentMetadata;
    bool public receivedMetadata;

    error CallbackFailed();

    constructor(address merchant_) {
        _merchant = merchant_;
    }

    function getMerchant() external view override returns (address) {
        return _merchant;
    }

    function processCallback(uint256 value) external {
        ++callCount;
        lastCallData = abi.encode(value);
    }

    function processCallbackWithMetadata(uint256 value, ZKPay.PaymentMetadata calldata metadata) external {
        ++callCount;
        lastCallData = abi.encode(value);
        lastPaymentMetadata = metadata;
        receivedMetadata = true;
    }

    function getLastPaymentMetadata() external view returns (ZKPay.PaymentMetadata memory) {
        return lastPaymentMetadata;
    }

    function failingCallback() external pure {
        revert CallbackFailed();
    }
}

contract MockInvalidMerchantContract is IMerchantCallback {
    event Processed(uint256 value);

    function getMerchant() external pure override returns (address) {
        return address(0x999);
    }
}

contract MockContractWithoutGetMerchant {
    event Processed(uint256 value);

    function processCallback(uint256 value) external {
        emit Processed(value);
    }
}

contract PaymentFunctionsTest is Test {
    ZKPay public zkpay;
    address public owner;
    address public treasury;
    MockERC20 public usdc;
    uint248 public usdcAmount;
    address public targetMerchant;
    uint64 public itemId;
    address public onBehalfOf;
    bytes public memoBytes;

    function _setupMerchantConfig() internal {
        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );
    }

    function _setupCallbackConfig(address contractAddress, bytes4 funcSig) internal {
        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: contractAddress,
                funcSig: funcSig,
                includePaymentMetadata: false
            })
        );
    }

    function _approveUSDC() internal {
        IERC20(USDC).approve(address(zkpay), usdcAmount);
    }

    function _getOnBehalfOfBytes32() internal view returns (bytes32) {
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

        owner = vm.addr(0x1);
        treasury = vm.addr(0x2);
        onBehalfOf = vm.addr(0x3);
        targetMerchant = vm.addr(0x4);
        itemId = 123;

        memoBytes = abi.encode(itemId);

        vm.startPrank(owner);

        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol", owner, abi.encodeCall(ZKPay.initialize, (owner, treasury, SXT, DummyData.getSwapLogicConfig()))
        );
        zkpay = ZKPay(zkPayProxyAddress);

        usdc = MockERC20(USDC);

        deal(USDC, address(this), 100e6);

        address usdcPriceFeed = address(new MockV3Aggregator(8, 1e8));

        zkpay.setPaymentAsset(
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

    function testSendInsufficientPayment() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        vm.prank(targetMerchant);
        zkpay.setPaywallItemPrice(bytes32(uint256(itemId)), usdcAmount * 1e12 + 1);

        vm.expectRevert();
        zkpay.send(USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)));
    }

    function testSendWithProtocolFee() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);
        zkpay.send(USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0));

        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);

        assertEq(IERC20(USDC).balanceOf(treasury), protocolFeeAmount);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendWithoutProtocolFee() public {
        uint248 sxtAmount = 100e18;
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.startPrank(owner);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 10e8));
        zkpay.setPaymentAsset(
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
        IERC20(SXT).approve(address(zkpay), sxtAmount);
        zkpay.send(SXT, sxtAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0));

        assertEq(IERC20(SXT).balanceOf(treasury), 0);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendToZeroAddress() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        vm.expectRevert();
        zkpay.send(USDC, usdcAmount, onBehalfOfBytes32, ZERO_ADDRESS, memoBytes, bytes32(0));
    }

    function testSendWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);

        vm.expectRevert();
        zkpay.send(invalidAsset, 100, bytes32(uint256(uint160(onBehalfOf))), targetMerchant, memoBytes, bytes32(0));
    }

    function testSendWithCallbackHappyPath() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(42);

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.processCallback.selector);

        zkpay.sendWithCallback(
            USDC, usdcAmount, _getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        assertEq(IERC20(USDC).balanceOf(treasury), protocolFeeAmount);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 42);
    }

    function testSendWithCallbackWithoutProtocolFee() public {
        uint248 sxtAmount = 100e18;

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.startPrank(owner);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 10e8));
        zkpay.setPaymentAsset(
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

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false
            })
        );

        deal(SXT, address(this), sxtAmount);
        IERC20(SXT).approve(address(zkpay), sxtAmount);

        zkpay.sendWithCallback(
            SXT, sxtAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(IERC20(SXT).balanceOf(treasury), 0);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);

        assertEq(callbackContract.callCount(), 1);
    }

    function testSendWithCallbackWithCallbackData() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(999);

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.processCallback.selector);

        zkpay.sendWithCallback(
            USDC, usdcAmount, _getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 999);
    }

    function testSendWithCallbackExecutorInteraction() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(555);

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.processCallback.selector);

        assertEq(callbackContract.callCount(), 0);

        zkpay.sendWithCallback(
            USDC, usdcAmount, _getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 555);
    }

    function testSendWithCallbackInvalidMerchant() public {
        MockInvalidMerchantContract invalidCallbackContract = new MockInvalidMerchantContract();
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(invalidCallbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false
            })
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        vm.expectRevert(ZKPay.InvalidMerchant.selector);
        zkpay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testSendWithCallbackToZeroAddress() public {
        new MockCallbackContract(ZERO_ADDRESS);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        vm.expectRevert();
        zkpay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, ZERO_ADDRESS, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testSendWithCallbackWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false
            })
        );

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.sendWithCallback(
            invalidAsset,
            100,
            bytes32(uint256(uint160(onBehalfOf))),
            targetMerchant,
            memoBytes,
            bytes32(uint256(itemId)),
            callbackData
        );
    }

    function testSendWithCallbackContractCallFailure() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode();

        _setupStandardCallbackTest(address(callbackContract), MockCallbackContract.failingCallback.selector);

        vm.expectRevert();
        zkpay.sendWithCallback(
            USDC, usdcAmount, _getOnBehalfOfBytes32(), targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );
    }

    function testSendWithCallbackItemIdGeneration() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes4 selector = bytes4(callbackData);
        bytes32 expectedItemId = keccak256(abi.encode(address(callbackContract), selector));

        assertTrue(expectedItemId != bytes32(0));

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false
            })
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testFuzzSendWithCallbackAmount(uint248 amount) public {
        vm.assume(amount >= 1000 && amount <= 1000e6);

        deal(USDC, address(this), amount);

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false
            })
        );

        IERC20(USDC).approve(address(zkpay), amount);

        zkpay.sendWithCallback(
            USDC, amount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testFuzzSendWithCallbackMemo(bytes calldata memo) public {
        vm.assume(memo.length <= 1000);

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false
            })
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memo, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testSendWithCallbackWithoutGetMerchantMethod() public {
        bytes memory callbackData = abi.encodeWithSelector(MockERC20.mint.selector, address(this), 1000);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert();
        zkpay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        MockContractWithoutGetMerchant contractWithoutGetMerchant = new MockContractWithoutGetMerchant();
        contractWithoutGetMerchant.processCallback(42);
    }

    function testSendWithCallbackInvalidItemId() public {
        bytes memory callbackData = abi.encode(42);
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        vm.expectRevert(ZKPay.InvalidItemId.selector);
        zkpay.sendWithCallback(USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0), callbackData);
    }

    function testSettleAuthorizedPaymentHappyPath() public {
        address client = address(this);
        uint248 sxtAmount = 100 ether;
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.startPrank(owner);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 10e8));
        zkpay.setPaymentAsset(
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
        IERC20(SXT).approve(address(zkpay), sxtAmount);

        zkpay.authorize(SXT, sxtAmount, onBehalfOfBytes32, targetMerchant, "test", bytes32(0));

        bytes32 transactionHash = EscrowPayment.generateTransactionHash(
            EscrowPayment.Transaction({asset: SXT, amount: sxtAmount, from: client, to: targetMerchant}), 1
        );

        // validate emitted event
        vm.expectEmit(true, true, true, false);
        emit IZKPay.AuthorizedPaymentSettled(SXT, sxtAmount, USDC, 0, 0, 0, client, targetMerchant, transactionHash);
        zkpay.settleAuthorizedPayment(SXT, sxtAmount, client, targetMerchant, transactionHash, 5 ether);

        assertLt(IERC20(SXT).balanceOf(client), sxtAmount);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendPathOverride() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        zkpay.sendPathOverride(customPath, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0));

        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);

        assertEq(IERC20(USDC).balanceOf(treasury), protocolFeeAmount);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendWithCallbackPathOverride() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallback.selector,
                includePaymentMetadata: false
            })
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallbackPathOverride(
            customPath, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        assertEq(IERC20(USDC).balanceOf(treasury), protocolFeeAmount);
        assertGt(IERC20(USDC).balanceOf(targetMerchant), 0);
    }

    function testSendWithCallbackWithPaymentMetadata() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(999);
        bytes32 onBehalfOfBytes32 = _getOnBehalfOfBytes32();

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallbackWithMetadata.selector,
                includePaymentMetadata: true
            })
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallback(
            USDC, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 999);
        assertTrue(callbackContract.receivedMetadata());

        ZKPay.PaymentMetadata memory metadata = callbackContract.getLastPaymentMetadata();
        assertEq(metadata.payoutToken, USDC);
        assertGt(metadata.payoutAmount, 0);
        assertGt(metadata.amountInUSD, 0);
        assertEq(metadata.onBehalfOf, onBehalfOfBytes32);
        assertEq(metadata.sender, address(this));
        assertEq(metadata.itemId, bytes32(uint256(itemId)));
    }

    function testSendWithCallbackPathOverrideWithPaymentMetadata() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encode(777);
        bytes32 onBehalfOfBytes32 = _getOnBehalfOfBytes32();
        bytes memory customPath = DummyData.getOriginAssetPath(USDC);

        vm.prank(targetMerchant);
        zkpay.setMerchantConfig(
            MerchantLogic.MerchantConfig({payoutToken: USDC, payoutAddress: targetMerchant, fulfillerPercentage: 0}),
            DummyData.getDestinationAssetPath(USDC)
        );

        vm.prank(targetMerchant);
        zkpay.setItemIdCallbackConfig(
            bytes32(uint256(itemId)),
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockCallbackContract.processCallbackWithMetadata.selector,
                includePaymentMetadata: true
            })
        );

        IERC20(USDC).approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallbackPathOverride(
            customPath, usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 777);
        assertTrue(callbackContract.receivedMetadata());

        ZKPay.PaymentMetadata memory metadata = callbackContract.getLastPaymentMetadata();
        assertEq(metadata.payoutToken, USDC);
        assertGt(metadata.payoutAmount, 0);
        assertGt(metadata.amountInUSD, 0);
        assertEq(metadata.onBehalfOf, onBehalfOfBytes32);
        assertEq(metadata.sender, address(this));
        assertEq(metadata.itemId, bytes32(uint256(itemId)));
    }
}
