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
        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddress: address(3),
            fulfillerPercentage: 5 * MerchantLogic.PERCENTAGE_PRECISION
        });

        vm.expectEmit(true, true, true, true);
        emit MerchantLogic.MerchantConfigSet(
            address(this), merchantConfig.payoutToken, merchantConfig.payoutAddress, merchantConfig.fulfillerPercentage
        );
        _zkpay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));

        MerchantLogic.MerchantConfig memory r = _zkpay.getMerchantConfig(address(this));
        assertEq(r.payoutToken, merchantConfig.payoutToken);
        assertEq(r.payoutAddress, merchantConfig.payoutAddress);
        assertEq(r.fulfillerPercentage, merchantConfig.fulfillerPercentage);
    }

    function testSetMerchantConfigInvalidPercentage() public {
        MerchantLogic.MerchantConfig memory merchantConfig = MerchantLogic.MerchantConfig({
            payoutToken: address(1),
            payoutAddress: address(3),
            fulfillerPercentage: MerchantLogic.MAX_PERCENTAGE + 1
        });

        vm.expectRevert(MerchantLogic.InvalidFulfillerPercentage.selector);
        _zkpay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));
    }

    function testSetMerchantConfigZeroPayoutAddress() public {
        MerchantLogic.MerchantConfig memory merchantConfig =
            MerchantLogic.MerchantConfig({payoutToken: address(1), payoutAddress: ZERO_ADDRESS, fulfillerPercentage: 1});

        vm.expectRevert(MerchantLogic.PayoutAddressCannotBeZero.selector);
        _zkpay.setMerchantConfig(merchantConfig, DummyData.getDestinationAssetPath(merchantConfig.payoutToken));
    }
}
