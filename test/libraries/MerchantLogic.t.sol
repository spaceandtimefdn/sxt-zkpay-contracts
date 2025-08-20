// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MerchantLogic} from "../../src/libraries/MerchantLogic.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";

contract MerchantLogicWrapper {
    mapping(address merchant => MerchantLogic.MerchantConfig) internal _configs;
    mapping(bytes32 itemId => MerchantLogic.ItemIdCallbackConfig) internal _itemIdCallbackConfigs;

    function set(address merchant, MerchantLogic.MerchantConfig calldata config) external {
        MerchantLogic.set(_configs, merchant, config);
    }

    function get(address merchant) external view returns (MerchantLogic.MerchantConfig memory config) {
        return MerchantLogic.get(_configs, merchant);
    }

    function setItemIdCallback(bytes32 itemId, MerchantLogic.ItemIdCallbackConfig calldata config) external {
        MerchantLogic.setItemIdCallback(_itemIdCallbackConfigs, itemId, config);
    }

    function getItemIdCallback(bytes32 itemId)
        external
        view
        returns (MerchantLogic.ItemIdCallbackConfig memory config)
    {
        return MerchantLogic.getItemIdCallback(_itemIdCallbackConfigs, itemId);
    }
}

contract MerchantLogicTest is Test {
    MerchantLogicWrapper internal _wrapper;

    function setUp() public {
        _wrapper = new MerchantLogicWrapper();
    }

    function testSetAndGet() public {
        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddress: address(2),
            fulfillerPercentage: 50 * MerchantLogic.PERCENTAGE_PRECISION
        });

        vm.expectEmit(true, true, true, true);
        emit MerchantLogic.MerchantConfigSet(
            address(this), merchantConfig.payoutToken, merchantConfig.payoutAddress, merchantConfig.fulfillerPercentage
        );
        _wrapper.set(address(this), merchantConfig);

        MerchantLogic.MerchantConfig memory result = _wrapper.get(address(this));
        assertEq(result.payoutToken, merchantConfig.payoutToken);
        assertEq(result.payoutAddress, merchantConfig.payoutAddress);
        assertEq(result.fulfillerPercentage, merchantConfig.fulfillerPercentage);
    }

    function testInvalidPercentage() public {
        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddress: address(2),
            fulfillerPercentage: MerchantLogic.MAX_PERCENTAGE + 1
        });

        vm.expectRevert(MerchantLogic.InvalidFulfillerPercentage.selector);
        _wrapper.set(address(this), merchantConfig);
    }

    function testZeroPayoutAddress() public {
        MerchantLogic.MerchantConfig memory merchantConfig =
            MerchantLogic.MerchantConfig({payoutToken: address(1), payoutAddress: ZERO_ADDRESS, fulfillerPercentage: 1});

        vm.expectRevert(MerchantLogic.PayoutAddressCannotBeZero.selector);
        _wrapper.set(address(this), merchantConfig);
    }

    function testSetAndGetItemIdCallback() public {
        bytes32 itemId = bytes32(uint256(123));
        MerchantLogic.ItemIdCallbackConfig memory callbackConfig =
            MerchantLogic.ItemIdCallbackConfig({contractAddress: address(1), funcSig: bytes4(0x12345678)});

        _wrapper.setItemIdCallback(itemId, callbackConfig);

        MerchantLogic.ItemIdCallbackConfig memory result = _wrapper.getItemIdCallback(itemId);
        assertEq(result.contractAddress, callbackConfig.contractAddress);
        assertEq(result.funcSig, callbackConfig.funcSig);
    }
}
