// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {DSPay} from "../src/DSPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MerchantLogic} from "../src/libraries/MerchantLogic.sol";
import {DummyData} from "./data/DummyData.sol";
import {ZERO_ADDRESS} from "../src/libraries/Constants.sol";

contract DSPayMerchantConfigTest is Test {
    DSPay internal _dspay;
    address internal _admin;
    address internal _priceFeed;
    address internal _sxt;

    function setUp() public {
        _admin = vm.addr(0x1);
        _priceFeed = address(new MockV3Aggregator(8, 1000));
        _sxt = vm.addr(0x3);

        vm.prank(_admin);
        _dspay = new DSPay(
            _admin,
            DummyData.getSwapLogicConfig(),
            AssetManagement.AssetManagementSequencerConfig({sequencerUptimeFeed: address(0), gracePeriod: 0})
        );
    }

    function testSetAndGetMerchantConfig() public {
        address[] memory addresses = new address[](2);
        addresses[0] = address(3);
        addresses[1] = address(4);
        uint32[] memory percentages = new uint32[](2);
        percentages[0] = 70 * MerchantLogic.PERCENTAGE_PRECISION;
        percentages[1] = 30 * MerchantLogic.PERCENTAGE_PRECISION;
        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages,
            allowUserCustomPath: true
        });

        vm.expectEmit(true, true, true, true);
        emit MerchantLogic.MerchantConfigSet(
            address(this),
            merchantConfig.payoutToken,
            merchantConfig.payoutAddresses,
            merchantConfig.payoutPercentages,
            merchantConfig.allowUserCustomPath
        );
        _dspay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));

        MerchantLogic.MerchantConfig memory r = _dspay.getMerchantConfig(address(this));
        assertEq(r.payoutToken, merchantConfig.payoutToken);
        assertEq(r.payoutAddresses.length, 2);
        assertEq(r.payoutAddresses[0], address(3));
        assertEq(r.payoutPercentages[0], 70 * MerchantLogic.PERCENTAGE_PRECISION);
        assertEq(r.payoutAddresses[1], address(4));
        assertEq(r.payoutPercentages[1], 30 * MerchantLogic.PERCENTAGE_PRECISION);
    }

    function testSetMerchantConfigZeroPayoutAddress() public {
        address[] memory addresses = new address[](1);
        addresses[0] = ZERO_ADDRESS;
        uint32[] memory percentages = new uint32[](1);
        percentages[0] = 100 * MerchantLogic.PERCENTAGE_PRECISION;
        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages,
            allowUserCustomPath: true
        });

        vm.expectRevert(MerchantLogic.PayoutAddressCannotBeZero.selector);
        _dspay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));
    }

    function testSetAndGetItemIdCallbackConfig() public {
        bytes32 itemId = bytes32(uint256(456));
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(2),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false,
            acceptedMethods: MerchantLogic.SEND_METHOD | MerchantLogic.AUTHORIZE_METHOD
        });

        _dspay.setItemIdCallbackConfig(itemId, config);

        MerchantLogic.ItemIdCallbackConfig memory result = _dspay.getItemIdCallbackConfig(address(this), itemId);
        assertEq(result.contractAddress, config.contractAddress);
        assertEq(result.funcSig, config.funcSig);
        assertEq(result.includePaymentMetadata, config.includePaymentMetadata);
        assertEq(result.acceptedMethods, config.acceptedMethods);
    }

    function testSetItemIdCallbackConfigZeroAcceptedMethods() public {
        bytes32 itemId = bytes32(uint256(456));
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(2),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false,
            acceptedMethods: bytes1(0)
        });

        vm.expectRevert(MerchantLogic.UnsupportedPaymentMethod.selector);
        _dspay.setItemIdCallbackConfig(itemId, config);
    }

    function testSetItemIdCallbackConfigInvalidAcceptedMethods() public {
        bytes32 itemId = bytes32(uint256(456));
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(2),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false,
            acceptedMethods: bytes1(0x08)
        });

        vm.expectRevert(MerchantLogic.UnsupportedPaymentMethod.selector);
        _dspay.setItemIdCallbackConfig(itemId, config);
    }

    function testSetItemIdCallbackConfigSendMethodOnly() public {
        bytes32 itemId = bytes32(uint256(456));
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(2),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false,
            acceptedMethods: MerchantLogic.SEND_METHOD
        });

        _dspay.setItemIdCallbackConfig(itemId, config);

        MerchantLogic.ItemIdCallbackConfig memory result = _dspay.getItemIdCallbackConfig(address(this), itemId);
        assertEq(result.acceptedMethods, MerchantLogic.SEND_METHOD);
    }

    function testSetItemIdCallbackConfigAuthorizeMethodOnly() public {
        bytes32 itemId = bytes32(uint256(456));
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(2),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false,
            acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
        });

        _dspay.setItemIdCallbackConfig(itemId, config);

        MerchantLogic.ItemIdCallbackConfig memory result = _dspay.getItemIdCallbackConfig(address(this), itemId);
        assertEq(result.acceptedMethods, MerchantLogic.AUTHORIZE_METHOD);
    }

    function testSetMerchantConfigTooManyRecipients() public {
        uint256 numRecipients = MerchantLogic.MAX_PAYOUT_RECIPIENTS + 1;
        address[] memory addresses = new address[](numRecipients);
        uint32[] memory percentages = new uint32[](numRecipients);

        uint32 percentagePerRecipient = MerchantLogic.TOTAL_PERCENTAGE / uint32(numRecipients);
        uint32 remainder = MerchantLogic.TOTAL_PERCENTAGE % uint32(numRecipients);

        for (uint256 i = 0; i < numRecipients; ++i) {
            addresses[i] = address(uint160(i + 1000));
            percentages[i] = percentagePerRecipient;
            if (i == 0) {
                percentages[i] += remainder;
            }
        }

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages,
            allowUserCustomPath: true
        });

        vm.expectRevert(MerchantLogic.TooManyPayoutRecipients.selector);
        _dspay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));
    }

    function testSetMerchantConfigMaxRecipients() public {
        uint256 numRecipients = MerchantLogic.MAX_PAYOUT_RECIPIENTS;
        address[] memory addresses = new address[](numRecipients);
        uint32[] memory percentages = new uint32[](numRecipients);

        uint32 percentagePerRecipient = MerchantLogic.TOTAL_PERCENTAGE / uint32(numRecipients);
        uint32 remainder = MerchantLogic.TOTAL_PERCENTAGE % uint32(numRecipients);

        for (uint256 i = 0; i < numRecipients; ++i) {
            addresses[i] = address(uint160(i + 1000));
            percentages[i] = percentagePerRecipient;
            if (i == 0) {
                percentages[i] += remainder;
            }
        }

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages,
            allowUserCustomPath: true
        });

        _dspay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));

        MerchantLogic.MerchantConfig memory result = _dspay.getMerchantConfig(address(this));
        assertEq(result.payoutAddresses.length, numRecipients);
        assertEq(result.payoutAddresses[0], address(1000));
        assertEq(result.payoutAddresses[numRecipients - 1], address(uint160(1000 + numRecipients - 1)));
    }
}
