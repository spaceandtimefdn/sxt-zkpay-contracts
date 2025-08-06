// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentLogic} from "../../src/module/PaymentLogic.sol";
import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../../src/libraries/Constants.sol";

contract PaymentLogicTestWrapper {
    function calculateProtocolFee(address asset, uint248 amount, address sxt)
        external
        pure
        returns (uint248 protocolFeeAmount, uint248 remainingAmount)
    {
        return PaymentLogic._calculateProtocolFee(asset, amount, sxt);
    }
}

contract PaymentLogicTest is Test {
    PaymentLogicTestWrapper internal _wrapper;
    address internal constant SXT_TOKEN = address(0x1);
    address internal constant OTHER_TOKEN = address(0x2);

    function setUp() public {
        _wrapper = new PaymentLogicTestWrapper();
    }

    function testCalculateProtocolFeeWithSXTToken() public view {
        uint248 amount = 1000 ether;

        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            _wrapper.calculateProtocolFee(SXT_TOKEN, amount, SXT_TOKEN);

        assertEq(protocolFeeAmount, 0);
        assertEq(remainingAmount, amount);
    }

    function testCalculateProtocolFeeWithOtherToken() public view {
        uint248 amount = 1000 ether;
        uint248 expectedProtocolFee = uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        uint248 expectedRemainingAmount = amount - expectedProtocolFee;

        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            _wrapper.calculateProtocolFee(OTHER_TOKEN, amount, SXT_TOKEN);

        assertEq(protocolFeeAmount, expectedProtocolFee);
        assertEq(remainingAmount, expectedRemainingAmount);
    }

    function testCalculateProtocolFeeZeroAmount() public view {
        uint248 amount = 0;

        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            _wrapper.calculateProtocolFee(OTHER_TOKEN, amount, SXT_TOKEN);

        assertEq(protocolFeeAmount, 0);
        assertEq(remainingAmount, 0);
    }

    function testFuzzCalculateProtocolFee(address asset, uint248 amount) public view {
        (uint248 protocolFeeAmount, uint248 remainingAmount) = _wrapper.calculateProtocolFee(asset, amount, SXT_TOKEN);

        if (asset == SXT_TOKEN) {
            assertEq(protocolFeeAmount, 0);
            assertEq(remainingAmount, amount);
        } else {
            uint248 expectedProtocolFee = uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
            assertEq(protocolFeeAmount, expectedProtocolFee);
            assertEq(remainingAmount, amount - expectedProtocolFee);
        }

        assertEq(protocolFeeAmount + remainingAmount, amount);
    }

    function testCalculateProtocolFeeWithSpecificValues() public view {
        uint248[] memory testAmounts = new uint248[](8);
        testAmounts[0] = 1 ether;
        testAmounts[1] = 100 ether;
        testAmounts[2] = 10000 ether;
        testAmounts[3] = 1000000 ether;
        testAmounts[4] = 1;
        testAmounts[5] = 1e3;
        testAmounts[6] = 1e6;
        testAmounts[7] = 1e9;

        uint256 length = testAmounts.length;
        for (uint256 i = 0; i < length; ++i) {
            uint248 amount = testAmounts[i];
            uint248 expectedProtocolFee = uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);

            (uint248 protocolFeeAmount, uint248 remainingAmount) =
                _wrapper.calculateProtocolFee(OTHER_TOKEN, amount, SXT_TOKEN);

            assertEq(protocolFeeAmount, expectedProtocolFee);
            assertEq(remainingAmount, amount - expectedProtocolFee);
            assertEq(protocolFeeAmount + remainingAmount, amount);
        }
    }
}
