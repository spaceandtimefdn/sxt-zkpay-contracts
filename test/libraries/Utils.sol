// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Utils} from "../../src/libraries/Utils.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";

contract UtilsTest is Test {
    function testIsContract() public view {
        assertTrue(Utils.isContract(address(this)));
        assertFalse(Utils.isContract(ZERO_ADDRESS));
        assertFalse(Utils.isContract(address(0x1)));
    }
}
