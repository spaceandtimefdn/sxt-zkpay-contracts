// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {NATIVE_ADDRESS, FEE, FEE_PRECISION} from "../src/libraries/Constants.sol";

contract PaymentFunctionsTest is Test {
    ZKPay public zkpay;
    address public owner;
    address public treasury;
    address public nativeTokenPriceFeed;
    MockERC20 public usdc;
    uint248 public usdcAmount;
    uint248 public nativeAmount;
    address public targetProtocol;
    uint64 public itemId;
    address public onBehalfOf;
    bytes public memoBytes;

    event SendPayment(
        address indexed asset,
        uint248 amount,
        uint248 protocolFeeAmount,
        bytes32 onBehalfOf,
        address indexed target,
        bytes memo,
        uint248 amountInUSD,
        address indexed sender
    );

    function setUp() public {
        uint8 nativeTokenDecimals = 18;
        int256 nativeTokenPrice = 1000e8; // 1 ETH = $1000
        usdcAmount = 10e6; // 10 USDC
        nativeAmount = 0.01 ether; // 1000 * 0.01 = $10

        owner = vm.addr(0x1);
        treasury = vm.addr(0x2);
        onBehalfOf = vm.addr(0x3);
        targetProtocol = vm.addr(0x4);
        itemId = 123;

        // Convert itemId to bytes for the new parameter type
        memoBytes = abi.encode(itemId);

        vm.startPrank(owner);

        // Deploy zkpay
        nativeTokenPriceFeed = address(new MockV3Aggregator(8, nativeTokenPrice));

        address sxt = address(new MockERC20());
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            owner,
            abi.encodeCall(ZKPay.initialize, (owner, treasury, sxt, nativeTokenPriceFeed, nativeTokenDecimals, 1000))
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
                allowedPaymentTypes: bytes1(0x01), // Allow Send payment type (0x01)
                priceFeed: usdcPriceFeed,
                tokenDecimals: 6,
                stalePriceThresholdInSeconds: 1000
            })
        );

        // Update native token to support Send payment type
        zkpay.setPaymentAsset(
            NATIVE_ADDRESS,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: bytes1(0x01), // Allow Send payment type (0x01)
                priceFeed: nativeTokenPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            })
        );

        vm.stopPrank();
    }

    function testSend() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);
        zkpay.send(address(usdc), usdcAmount, onBehalfOfBytes32, targetProtocol, memoBytes);

        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * FEE) / FEE_PRECISION);

        assertEq(usdc.balanceOf(targetProtocol), usdcAmount - protocolFeeAmount);
        assertEq(usdc.balanceOf(treasury), protocolFeeAmount);
    }

    function testSendNotErc20Token() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.expectRevert(ZKPay.NotErc20Token.selector);
        zkpay.send(NATIVE_ADDRESS, nativeAmount, onBehalfOfBytes32, targetProtocol, memoBytes);
    }

    function testSendToZeroAddress() public {
        // Convert onBehalfOf address to bytes32
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        // Approve the ZKPay contract to spend our USDC
        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert(AssetManagement.TargetAddressCannotBeZero.selector);
        // Call the send function
        zkpay.send(address(usdc), usdcAmount, onBehalfOfBytes32, address(0), memoBytes);
    }

    function testSendNative() public {
        vm.deal(address(this), nativeAmount);

        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        // Expect the Payment event to be emitted with correct parameters
        vm.expectEmit(true, true, true, false); // Don't check the amountInUSD
        emit SendPayment(
            NATIVE_ADDRESS,
            nativeAmount,
            uint248((uint256(nativeAmount) * 9000) / 1_000_000),
            onBehalfOfBytes32,
            targetProtocol,
            memoBytes,
            0,
            address(this)
        );

        zkpay.sendNative{value: nativeAmount}(onBehalfOfBytes32, targetProtocol, memoBytes);

        uint248 protocolFeeAmount = uint248((uint256(nativeAmount) * FEE) / FEE_PRECISION);
        assertEq(targetProtocol.balance, nativeAmount - protocolFeeAmount);
        assertEq(treasury.balance, protocolFeeAmount);
    }

    function testSendNativeToZeroAddres() public {
        // Fund the test contract with ETH
        vm.deal(address(this), nativeAmount);

        // Convert onBehalfOf address to bytes32
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.expectRevert(AssetManagement.TargetAddressCannotBeZero.selector);
        // Call the sendNative function
        zkpay.sendNative{value: nativeAmount}(onBehalfOfBytes32, address(0), memoBytes);
    }

    function testSendWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.send(invalidAsset, 100, bytes32(uint256(uint160(onBehalfOf))), targetProtocol, memoBytes);
    }

    function testSendWithUnsupportedPaymentType() public {
        // Create a new asset that doesn't support Send payment type
        address newToken = address(new MockERC20());
        address newTokenPriceFeed = address(new MockV3Aggregator(8, 1e8));

        vm.startPrank(owner);
        zkpay.setPaymentAsset(
            newToken,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: bytes1(0x02), // Only Query payment type (0x02), not Send (0x01)
                priceFeed: newTokenPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            })
        );
        vm.stopPrank();

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.send(newToken, usdcAmount, bytes32(uint256(uint160(onBehalfOf))), targetProtocol, memoBytes);
    }

    function testSendNativeWithUnsupportedPaymentType() public {
        // Set up payment asset with unsupported payment type
        AssetManagement.PaymentAsset memory paymentAssetInstance = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.QUERY_PAYMENT_FLAG, // Only query payments allowed
            priceFeed: nativeTokenPriceFeed,
            tokenDecimals: 18,
            stalePriceThresholdInSeconds: 1000
        });

        vm.prank(owner);
        zkpay.setPaymentAsset(NATIVE_ADDRESS, paymentAssetInstance);

        // Convert onBehalfOf address to bytes32
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        // Fund the test contract with ETH
        vm.deal(address(this), nativeAmount);

        // Expect revert because the asset doesn't support SEND payment type
        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.sendNative{value: nativeAmount}(onBehalfOfBytes32, targetProtocol, memoBytes);
    }

    receive() external payable {}
}
