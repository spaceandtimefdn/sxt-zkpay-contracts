// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MerchantLogic} from "../../src/libraries/MerchantLogic.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";

contract MerchantLogicWrapper {
    MerchantLogic.MerchantLogicStorage internal _merchantLogicStorage;

    function setConfig(address merchant, MerchantLogic.MerchantConfig calldata config) external {
        MerchantLogic.setConfig(_merchantLogicStorage, merchant, config);
    }

    function getConfig(address merchant) external view returns (MerchantLogic.MerchantConfig memory config) {
        return MerchantLogic.getConfig(_merchantLogicStorage, merchant);
    }

    function setItemIdCallback(address merchant, bytes32 itemId, MerchantLogic.ItemIdCallbackConfig calldata config)
        external
    {
        MerchantLogic.setItemIdCallback(_merchantLogicStorage, merchant, itemId, config);
    }

    function getItemIdCallback(address merchant, bytes32 itemId)
        external
        view
        returns (MerchantLogic.ItemIdCallbackConfig memory config)
    {
        return MerchantLogic.getItemIdCallback(_merchantLogicStorage, merchant, itemId);
    }
}

contract MerchantLogicTest is Test {
    MerchantLogicWrapper internal _wrapper;

    function setUp() public {
        _wrapper = new MerchantLogicWrapper();
    }

    function testSetAndGet() public {
        address[] memory addresses = new address[](2);
        addresses[0] = address(2);
        addresses[1] = address(3);

        uint32[] memory percentages = new uint32[](2);
        percentages[0] = 60;
        percentages[1] = 40;

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });

        vm.expectEmit(true, true, true, true);
        emit MerchantLogic.MerchantConfigSet(
            address(this), merchantConfig.payoutToken, merchantConfig.payoutAddresses, merchantConfig.payoutPercentages
        );
        _wrapper.setConfig(address(this), merchantConfig);

        MerchantLogic.MerchantConfig memory result = _wrapper.getConfig(address(this));
        assertEq(result.payoutToken, merchantConfig.payoutToken);
        assertEq(result.payoutAddresses.length, 2);
        assertEq(result.payoutAddresses[0], address(2));
        assertEq(result.payoutPercentages[0], 60);
        assertEq(result.payoutAddresses[1], address(3));
        assertEq(result.payoutPercentages[1], 40);
    }

    function testZeroPayoutAddress() public {
        address[] memory addresses = new address[](1);
        addresses[0] = ZERO_ADDRESS;

        uint32[] memory percentages = new uint32[](1);
        percentages[0] = 100;

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });

        vm.expectRevert(MerchantLogic.PayoutAddressCannotBeZero.selector);
        _wrapper.setConfig(address(this), merchantConfig);
    }

    function testSetAndGetItemIdCallback() public {
        address merchant = address(this);
        bytes32 itemId = bytes32(uint256(123));
        MerchantLogic.ItemIdCallbackConfig memory callbackConfig = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(1),
            funcSig: bytes4(0x12345678),
            includePaymentMetadata: false
        });

        _wrapper.setItemIdCallback(merchant, itemId, callbackConfig);

        MerchantLogic.ItemIdCallbackConfig memory result = _wrapper.getItemIdCallback(merchant, itemId);
        assertEq(result.contractAddress, callbackConfig.contractAddress);
        assertEq(result.funcSig, callbackConfig.funcSig);
        assertEq(result.includePaymentMetadata, callbackConfig.includePaymentMetadata);
    }

    function testInvalidPercentageSum() public {
        address[] memory addresses = new address[](2);
        addresses[0] = address(2);
        addresses[1] = address(3);

        uint32[] memory percentages = new uint32[](2);
        percentages[0] = 50;
        percentages[1] = 30;

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });

        vm.expectRevert(MerchantLogic.InvalidPayoutPercentageSum.selector);
        _wrapper.setConfig(address(this), merchantConfig);
    }

    function testNoPayoutRecipients() public {
        address[] memory addresses = new address[](0);
        uint32[] memory percentages = new uint32[](0);

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });

        vm.expectRevert(MerchantLogic.NoPayoutRecipients.selector);
        _wrapper.setConfig(address(this), merchantConfig);
    }

    function testMismatchedArrayLengths() public {
        address[] memory addresses = new address[](2);
        addresses[0] = address(2);
        addresses[1] = address(3);

        uint32[] memory percentages = new uint32[](3);
        percentages[0] = 50;
        percentages[1] = 30;
        percentages[2] = 20;

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });

        vm.expectRevert(MerchantLogic.PayoutArrayLengthMismatch.selector);
        _wrapper.setConfig(address(this), merchantConfig);
    }

    function testZeroPercentage() public {
        address[] memory addresses = new address[](3);
        addresses[0] = address(2);
        addresses[1] = address(3);
        addresses[2] = address(4);

        uint32[] memory percentages = new uint32[](3);
        percentages[0] = 50;
        percentages[1] = 0;
        percentages[2] = 50;

        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });

        vm.expectRevert(MerchantLogic.ZeroPayoutPercentage.selector);
        _wrapper.setConfig(address(this), merchantConfig);
    }
}
