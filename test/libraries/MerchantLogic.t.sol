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
        MerchantLogic.MerchantConfig memory merchantConfig =
            MerchantLogic.MerchantConfig({payoutToken: address(1), payoutAddress: address(2)});

        vm.expectEmit(true, true, true, true);
        emit MerchantLogic.MerchantConfigSet(address(this), merchantConfig.payoutToken, merchantConfig.payoutAddress);
        _wrapper.setConfig(address(this), merchantConfig);

        MerchantLogic.MerchantConfig memory result = _wrapper.getConfig(address(this));
        assertEq(result.payoutToken, merchantConfig.payoutToken);
        assertEq(result.payoutAddress, merchantConfig.payoutAddress);
    }

    function testZeroPayoutAddress() public {
        MerchantLogic.MerchantConfig memory merchantConfig =
            MerchantLogic.MerchantConfig({payoutToken: address(1), payoutAddress: ZERO_ADDRESS});

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
}
