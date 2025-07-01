// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PayWallLogic} from "../../src/libraries/PayWallLogic.sol";

contract PayWallLogicTest is Test {
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;

    address internal constant MERCHANT = address(0x1234);
    bytes32 internal constant ITEM = bytes32(uint256(0x5678));
    uint248 internal constant PRICE = 1 ether; // 1 USD

    PayWallLogic.PayWallLogicStorage internal _paywallLogicStorage;

    function setUp() public {
        _paywallLogicStorage.setItemPrice(MERCHANT, ITEM, PRICE);
    }

    function testGetItemPrice() public view {
        assertEq(_paywallLogicStorage.getItemPrice(MERCHANT, ITEM), PRICE);
    }

    function testSetItemPrice() public {
        uint248 newPrice = 2 ether; // 2 USD

        vm.expectEmit(true, true, true, true);
        emit PayWallLogic.ItemPriceSet(MERCHANT, ITEM, newPrice);

        _paywallLogicStorage.setItemPrice(MERCHANT, ITEM, newPrice);
        assertEq(_paywallLogicStorage.getItemPrice(MERCHANT, ITEM), newPrice);
    }
}
