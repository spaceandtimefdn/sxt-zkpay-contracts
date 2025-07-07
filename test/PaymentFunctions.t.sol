// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {NATIVE_ADDRESS, PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../src/libraries/Constants.sol";
import {DummyData} from "./data/DummyData.sol";
import {IZKPay} from "../src/interfaces/IZKPay.sol";

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
            abi.encodeCall(
                ZKPay.initialize,
                (owner, treasury, sxt, nativeTokenPriceFeed, nativeTokenDecimals, 1000, DummyData.getSwapLogicConfig())
            )
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
            }),
            DummyData.getOriginAssetPath(address(usdc))
        );

        // Update native token to support Send payment type
        zkpay.setPaymentAsset(
            NATIVE_ADDRESS,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: bytes1(0x01), // Allow Send payment type (0x01)
                priceFeed: nativeTokenPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(NATIVE_ADDRESS)
        );

        vm.stopPrank();
    }

    function testSendWithProtocolFee() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        usdc.approve(address(zkpay), usdcAmount);
        zkpay.send(address(usdc), usdcAmount, onBehalfOfBytes32, targetProtocol, memoBytes, bytes32(0));

        uint248 protocolFeeAmount = uint248((uint256(usdcAmount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);

        assertEq(usdc.balanceOf(targetProtocol), usdcAmount - protocolFeeAmount);
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
                allowedPaymentTypes: bytes1(0x01),
                priceFeed: sxtPriceFeed,
                tokenDecimals: 18,
                stalePriceThresholdInSeconds: 1000
            }),
            DummyData.getOriginAssetPath(sxtToken)
        );
        vm.stopPrank();

        sxt.approve(address(zkpay), sxtAmount);
        zkpay.send(sxtToken, sxtAmount, onBehalfOfBytes32, targetProtocol, memoBytes, bytes32(0));

        assertEq(sxt.balanceOf(targetProtocol), sxtAmount);
        assertEq(sxt.balanceOf(treasury), 0);
    }

    function testSendNotErc20Token() public {
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        vm.expectRevert(ZKPay.NotErc20Token.selector);
        zkpay.send(NATIVE_ADDRESS, nativeAmount, onBehalfOfBytes32, targetProtocol, memoBytes, bytes32(0));
    }

    function testSendToZeroAddress() public {
        // Convert onBehalfOf address to bytes32
        bytes32 onBehalfOfBytes32 = bytes32(uint256(uint160(onBehalfOf)));

        // Approve the ZKPay contract to spend our USDC
        usdc.approve(address(zkpay), usdcAmount);

        vm.expectRevert(AssetManagement.TargetAddressCannotBeZero.selector);
        // Call the send function
        zkpay.send(address(usdc), usdcAmount, onBehalfOfBytes32, address(0), memoBytes, bytes32(0));
    }

    function testSendWithUnsupportedAsset() public {
        address invalidAsset = vm.addr(0x5);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.send(invalidAsset, 100, bytes32(uint256(uint160(onBehalfOf))), targetProtocol, memoBytes, bytes32(0));
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
            }),
            DummyData.getOriginAssetPath(newToken)
        );
        vm.stopPrank();

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.send(newToken, usdcAmount, bytes32(uint256(uint160(onBehalfOf))), targetProtocol, memoBytes, bytes32(0));
    }

    receive() external payable {}
}
