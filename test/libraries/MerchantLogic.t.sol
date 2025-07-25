// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MerchantLogic} from "../../src/libraries/MerchantLogic.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";

contract MerchantLogicWrapper {
    mapping(address merchant => MerchantLogic.MerchantConfig) internal _configs;

    function set(address merchant, MerchantLogic.MerchantConfig calldata config) external {
        MerchantLogic.set(_configs, merchant, config);
    }

    function get(address merchant) external view returns (MerchantLogic.MerchantConfig memory config) {
        return MerchantLogic.get(_configs, merchant);
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
}
