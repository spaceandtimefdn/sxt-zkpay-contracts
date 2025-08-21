// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {MerchantLogic} from "../src/libraries/MerchantLogic.sol";
import {DummyData} from "./data/DummyData.sol";
import {ZERO_ADDRESS} from "../src/libraries/Constants.sol";

contract ZKPayMerchantConfigTest is Test {
    ZKPay internal _zkpay;
    address internal _owner;
    address internal _treasury;
    address internal _priceFeed;
    address internal _sxt;

    function setUp() public {
        _owner = vm.addr(0x1);
        _treasury = vm.addr(0x2);
        _priceFeed = address(new MockV3Aggregator(8, 1000));
        _sxt = vm.addr(0x3);

        vm.prank(_owner);
        address proxy = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            _owner,
            abi.encodeCall(ZKPay.initialize, (_owner, _treasury, _sxt, DummyData.getSwapLogicConfig()))
        );
        _zkpay = ZKPay(proxy);
    }

    function testSetAndGetMerchantConfig() public {
        address[] memory addresses = new address[](2);
        addresses[0] = address(3);
        addresses[1] = address(4);
        uint32[] memory percentages = new uint32[](2);
        percentages[0] = 70;
        percentages[1] = 30;
        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddresses: addresses,
            payoutPercentages: percentages
        });

        vm.expectEmit(true, true, true, true);
        emit MerchantLogic.MerchantConfigSet(
            address(this), merchantConfig.payoutToken, merchantConfig.payoutAddresses, merchantConfig.payoutPercentages
        );
        _zkpay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));

        MerchantLogic.MerchantConfig memory r = _zkpay.getMerchantConfig(address(this));
        assertEq(r.payoutToken, merchantConfig.payoutToken);
        assertEq(r.payoutAddresses.length, 2);
        assertEq(r.payoutAddresses[0], address(3));
        assertEq(r.payoutPercentages[0], 70);
        assertEq(r.payoutAddresses[1], address(4));
        assertEq(r.payoutPercentages[1], 30);
    }

    function testSetMerchantConfigZeroPayoutAddress() public {
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
        _zkpay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));
    }

    function testSetAndGetItemIdCallbackConfig() public {
        bytes32 itemId = bytes32(uint256(456));
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(2),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false
        });

        _zkpay.setItemIdCallbackConfig(itemId, config);

        MerchantLogic.ItemIdCallbackConfig memory result = _zkpay.getItemIdCallbackConfig(address(this), itemId);
        assertEq(result.contractAddress, config.contractAddress);
        assertEq(result.funcSig, config.funcSig);
        assertEq(result.includePaymentMetadata, config.includePaymentMetadata);
    }

    function testSetItemIdCallbackConfigInvalidItemId() public {
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(2),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false
        });

        vm.expectRevert(ZKPay.InvalidItemId.selector);
        _zkpay.setItemIdCallbackConfig(bytes32(0), config);
    }

    function testSetItemIdCallbackConfigInvalidContract() public {
        bytes32 itemId = bytes32(uint256(456));
        MerchantLogic.ItemIdCallbackConfig memory config = MerchantLogic.ItemIdCallbackConfig({
            contractAddress: address(0),
            funcSig: bytes4(0x87654321),
            includePaymentMetadata: false
        });

        vm.expectRevert(ZKPay.InvalidCallbackContract.selector);
        _zkpay.setItemIdCallbackConfig(itemId, config);
    }
}
