// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../src/libraries/Constants.sol";
import {DummyData} from "./data/DummyData.sol";
import {IMerchantCallback} from "../src/interfaces/IMerchantCallback.sol";

contract MockCallbackContract is IMerchantCallback {
    address private _merchant;
    uint256 public callCount;
    bytes public lastCallData;

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

    function failingCallback() external pure {
        revert CallbackFailed();
    }
}

contract MockInvalidMerchantContract is IMerchantCallback {
    event Processed(uint256 value);

    function getMerchant() external pure override returns (address) {
        return address(0x999);
    }

    function processCallback(uint256 value) external {
        emit Processed(value);
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

    function setUp() public {
        usdcAmount = 10e6; // 10 USDC

        owner = vm.addr(0x1);
        treasury = vm.addr(0x2);
        onBehalfOf = vm.addr(0x3);
        targetMerchant = vm.addr(0x4);
        itemId = 123;

        // Convert itemId to bytes for the new parameter type
        memoBytes = abi.encode(itemId);

        vm.startPrank(owner);

        // Deploy zkpay
        address sxt = address(new MockERC20());
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol", owner, abi.encodeCall(ZKPay.initialize, (owner, treasury, sxt, DummyData.getSwapLogicConfig()))
        );
        zkpay = ZKPay(zkPayProxyAddress);

        // Deploy and configure USDC
        usdc = new MockERC20();
        usdc.mint(address(this), 100e6); // Mint 100 USDC to test contract

        address usdcPriceFeed = address(new MockV3Aggregator(8, 1e8)); // 1 USDC = $1

        // Set USDC as a supported payment asset with Send payment type
        zkpay.setPaymentAsset(
            address(usdc),
            AssetManagement.PaymentAsset({
                priceFeed: usdcPriceFeed,
                tokenDecimals: 6,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(address(usdc))
        );

        vm.stopPrank();
    }

    function testSendInsufficientPayment() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        vm.prank(targetMerchant);
        zkpay.setPaywallItemPrice(bytes32(uint256(itemId)), usdcAmount * 1e12 + 1);

        vm.expectRevert(ZKPay.InsufficientPayment.selector);
        zkpay.send(address(usdc), usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(uint256(itemId)));
    }

    function testSendWithProtocolFee() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);
        zkpay.send(address(usdc), usdcAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0));

        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);

        assertEq(usdc.balanceOf(targetMerchant), usdcAmount - protocolFeeAmount);
        assertEq(usdc.balanceOf(treasury), protocolFeeAmount);
    }

    function testSendWithoutProtocolFee() public {
        address sxtToken = zkpay.getSXT();
        MockERC20 sxt = MockERC20(sxtToken);

        sxt.mint(address(this), 1000e18);
        uint248 sxtAmount = 100e18;
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.startPrank(owner);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 1e8));
        zkpay.setPaymentAsset(
            sxtToken,
            AssetManagement.PaymentAsset({
                priceFeed: sxtPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(sxtToken)
        );
        vm.stopPrank();

        sxt.approve(address(zkpay), sxtAmount);
        zkpay.send(sxtToken, sxtAmount, onBehalfOfBytes32, targetMerchant, memoBytes, bytes32(0));

        assertEq(sxt.balanceOf(targetMerchant), sxtAmount);
        assertEq(sxt.balanceOf(treasury), 0);
    }

    function testSendToZeroAddress() public {
        // Convert onBehalfOf address to bytes32
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        // Approve the ZKPay contract to spend our USDC
        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert(AssetManagement.MerchantAddressCannotBeZero.selector);
        // Call the send function
        zkpay.send(address(usdc), usdcAmount, onBehalfOfBytes32, address(0), memoBytes, bytes32(0));
    }

    function testSendWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.send(invalidAsset, 100, bytes32(uint256(uint160(onBehalfOf))), targetMerchant, memoBytes, bytes32(0));
    }

    function testSendWithCallbackHappyPath() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallback(
            address(usdc),
            usdcAmount,
            onBehalfOfBytes32,
            targetMerchant,
            memoBytes,
            address(callbackContract),
            callbackData
        );

        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        assertEq(usdc.balanceOf(targetMerchant), usdcAmount - protocolFeeAmount);
        assertEq(usdc.balanceOf(treasury), protocolFeeAmount);

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 42);
    }

    function testSendWithCallbackWithoutProtocolFee() public {
        address sxtToken = zkpay.getSXT();
        MockERC20 sxt = MockERC20(sxtToken);

        sxt.mint(address(this), 1000e18);
        uint248 sxtAmount = 100e18;

        vm.startPrank(owner);
        address sxtPriceFeed = address(new MockV3Aggregator(8, 1e8));
        zkpay.setPaymentAsset(
            sxtToken,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: bytes1(0x01),
                priceFeed: sxtPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(sxtToken)
        );
        vm.stopPrank();

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 123);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        sxt.approve(address(zkpay), sxtAmount);

        zkpay.sendWithCallback(
            sxtToken, sxtAmount, onBehalfOfBytes32, targetMerchant, memoBytes, address(callbackContract), callbackData
        );

        assertEq(sxt.balanceOf(targetMerchant), sxtAmount);
        assertEq(sxt.balanceOf(treasury), 0);

        assertEq(callbackContract.callCount(), 1);
    }

    function testSendWithCallbackWithCallbackData() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 999);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallback(
            address(usdc),
            usdcAmount,
            onBehalfOfBytes32,
            targetMerchant,
            memoBytes,
            address(callbackContract),
            callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 999);
    }

    function testSendWithCallbackExecutorInteraction() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 555);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        assertEq(callbackContract.callCount(), 0);

        zkpay.sendWithCallback(
            address(usdc),
            usdcAmount,
            onBehalfOfBytes32,
            targetMerchant,
            memoBytes,
            address(callbackContract),
            callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 555);
    }

    function testSendWithCallbackInvalidMerchant() public {
        MockInvalidMerchantContract invalidCallbackContract = new MockInvalidMerchantContract();
        bytes memory callbackData = abi.encodeWithSelector(MockInvalidMerchantContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert(ZKPay.InvalidMerchant.selector);
        zkpay.sendWithCallback(
            address(usdc),
            usdcAmount,
            onBehalfOfBytes32,
            targetMerchant,
            memoBytes,
            address(invalidCallbackContract),
            callbackData
        );

        invalidCallbackContract.processCallback(42);
    }

    function testSendWithCallbackToZeroAddress() public {
        MockCallbackContract callbackContract = new MockCallbackContract(address(0));
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert(AssetManagement.MerchantAddressCannotBeZero.selector);
        zkpay.sendWithCallback(
            address(usdc), usdcAmount, onBehalfOfBytes32, address(0), memoBytes, address(callbackContract), callbackData
        );
    }

    function testSendWithCallbackWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.sendWithCallback(
            invalidAsset,
            100,
            bytes32(uint256(uint160(onBehalfOf))),
            targetMerchant,
            memoBytes,
            address(callbackContract),
            callbackData
        );
    }

    function testSendWithCallbackWithUnsupportedPaymentType() public {
        address newToken = address(new MockERC20());
        address newTokenPriceFeed = address(new MockV3Aggregator(8, 1e8));

        vm.startPrank(owner);
        zkpay.setPaymentAsset(
            newToken,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: bytes1(0x02),
                priceFeed: newTokenPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(newToken)
        );
        vm.stopPrank();

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.sendWithCallback(
            newToken,
            usdcAmount,
            bytes32(uint256(uint160(onBehalfOf))),
            targetMerchant,
            memoBytes,
            address(callbackContract),
            callbackData
        );
    }

    function testSendWithCallbackContractCallFailure() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.failingCallback.selector);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert();
        zkpay.sendWithCallback(
            address(usdc),
            usdcAmount,
            onBehalfOfBytes32,
            targetMerchant,
            memoBytes,
            address(callbackContract),
            callbackData
        );
    }

    function testSendWithCallbackItemIdGeneration() public {
        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes4 selector = bytes4(callbackData);
        bytes32 expectedItemId = keccak256(abi.encode(address(callbackContract), selector));

        assertTrue(expectedItemId != bytes32(0));

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallback(
            address(usdc),
            usdcAmount,
            onBehalfOfBytes32,
            targetMerchant,
            memoBytes,
            address(callbackContract),
            callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testFuzzSendWithCallbackAmount(uint248 amount) public {
        vm.assume(amount > 0 && amount <= 1000e6);

        usdc.mint(address(this), amount);

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), amount);

        zkpay.sendWithCallback(
            address(usdc), amount, onBehalfOfBytes32, targetMerchant, memoBytes, address(callbackContract), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testFuzzSendWithCallbackMemo(bytes calldata memo) public {
        vm.assume(memo.length <= 1000);

        MockCallbackContract callbackContract = new MockCallbackContract(targetMerchant);
        bytes memory callbackData = abi.encodeWithSelector(MockCallbackContract.processCallback.selector, 42);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        zkpay.sendWithCallback(
            address(usdc), usdcAmount, onBehalfOfBytes32, targetMerchant, memo, address(callbackContract), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
    }

    function testSendWithCallbackWithoutGetMerchantMethod() public {
        MockERC20 tokenContract = new MockERC20();
        bytes memory callbackData = abi.encodeWithSelector(MockERC20.mint.selector, address(this), 1000);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert();
        zkpay.sendWithCallback(
            address(usdc),
            usdcAmount,
            onBehalfOfBytes32,
            targetMerchant,
            memoBytes,
            address(tokenContract),
            callbackData
        );

        MockContractWithoutGetMerchant contractWithoutGetMerchant = new MockContractWithoutGetMerchant();
        contractWithoutGetMerchant.processCallback(42);
    }
}
