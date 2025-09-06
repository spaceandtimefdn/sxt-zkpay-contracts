// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RPC_URL, BLOCK_NUMBER, USDC, WETH, SXT, USDT, ROUTER} from "../data/MainnetConstants.sol";
import {TWAP} from "../../src/libraries/TWAP.sol";

contract TWAPTest is Test {
    using TWAP for bytes;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    uint256 private constant TEST_AMOUNT_USDC = 4300 * 1e6;
    uint256 private constant TEST_SLIPPAGE_2_PERCENT = 2;
    uint256 private constant TEST_SLIPPAGE_3_PERCENT = 3;
    uint256 private constant SLIPPAGE_1_PERCENT = 99;
    uint256 private constant SLIPPAGE_2_PERCENT = 98;
    uint256 private constant SLIPPAGE_5_PERCENT = 95;
    uint256 private constant FIRST_HOP_OFFSET = 23;

    address private constant USDC_WETH_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    address private constant SXT_USDT_POOL = 0x20c42D3513e9E7fafFf82173AA5327f02D5163e3;

    function setUp() public {
        vm.createSelectFork(RPC_URL, BLOCK_NUMBER);
    }

    function testGetNextPoolSimple() public pure {
        bytes memory path = abi.encodePacked(USDC, FEE_MEDIUM, WETH);
        (address tokenIn, address tokenOut, uint24 fee, uint256 restPtr) = path.getNextPool(0);
        assertEq(tokenIn, USDC);
        assertEq(tokenOut, WETH);
        assertEq(fee, FEE_MEDIUM);
        assertEq(restPtr, 0);
    }

    function testGetNextPoolWithTwapFork() public view {
        bytes memory path = abi.encodePacked(USDC, FEE_MEDIUM, WETH);

        address computedPool = TWAP.getPoolFromFactory(USDC, WETH, FEE_MEDIUM, ROUTER);
        assertEq(computedPool, USDC_WETH_POOL);

        (address tokenIn, address tokenOut, uint24 fee, uint256 restPtr, int24 tick, uint256 priceX96) =
            path.getNextPoolWithTwap(0, ROUTER);
        assertEq(tokenIn, USDC);
        assertEq(tokenOut, WETH);
        assertEq(fee, FEE_MEDIUM);
        assertEq(restPtr, 0);
        assertTrue(tick != 0);
        assertTrue(priceX96 != 0);
    }

    function testGetNextPoolTwoHops() public pure {
        bytes memory path = abi.encodePacked(USDC, FEE_MEDIUM, WETH, FEE_MEDIUM, SXT);
        (address tokenIn1, address tokenOut1, uint24 fee1, uint256 restPtr1) = path.getNextPool(0);
        assertEq(tokenIn1, USDC);
        assertEq(tokenOut1, WETH);
        assertEq(fee1, FEE_MEDIUM);
        assertEq(restPtr1, FIRST_HOP_OFFSET);
        (address tokenIn2, address tokenOut2, uint24 fee2, uint256 restPtr2) = path.getNextPool(restPtr1);
        assertEq(tokenIn2, WETH);
        assertEq(tokenOut2, SXT);
        assertEq(fee2, FEE_MEDIUM);
        assertEq(restPtr2, 0);
    }

    function testSXTUSDTPoolLookup() public view {
        address actualPool = TWAP.getPoolFromFactory(SXT, USDT, FEE_MEDIUM, ROUTER);

        assertEq(actualPool, SXT_USDT_POOL, "SXT/USDT pool matches");
        assertTrue(actualPool != address(0), "SXT/USDT pool should exist");
    }

    function testGetNextPoolWithTwapSXTUSDT() public view {
        bytes memory path = abi.encodePacked(SXT, FEE_MEDIUM, USDT);
        (address tokenIn, address tokenOut, uint24 fee, uint256 restPtr, int24 tick,) =
            path.getNextPoolWithTwap(0, ROUTER);

        assertEq(tokenIn, SXT);
        assertEq(tokenOut, USDT);
        assertEq(fee, FEE_MEDIUM);
        assertEq(restPtr, 0);

        assertTrue(tick != 0, "TWAP tick non-zero");
    }

    function testValidateSlippageTWAPSingleHop() public {
        bytes memory path = abi.encodePacked(USDC, FEE_MEDIUM, WETH);
        uint256 amountIn = TEST_AMOUNT_USDC;
        uint256 slippage = TEST_SLIPPAGE_2_PERCENT;

        uint256 actualAmountOut1 = 0.99 ether;
        TWAP.validateSlippageTWAP(path, amountIn, actualAmountOut1, slippage, ROUTER);

        uint256 actualAmountOut2 = 1.05 ether;
        vm.expectRevert(TWAP.SlippageExceeded.selector);
        this.callValidateSlippageTWAP(path, amountIn, actualAmountOut2, slippage);

        uint256 actualAmountOut3 = 0.97 ether;
        vm.expectRevert(TWAP.SlippageExceeded.selector);
        this.callValidateSlippageTWAP(path, amountIn, actualAmountOut3, slippage);
    }

    function callValidateSlippageTWAP(bytes calldata path, uint256 amountIn, uint256 amountOut, uint256 slippage)
        external
        view
    {
        TWAP.validateSlippageTWAP(path, amountIn, amountOut, slippage, ROUTER);
    }

    function testValidateSlippageTWAPMultiHop() public {
        bytes memory path = abi.encodePacked(USDC, FEE_MEDIUM, WETH, FEE_LOW, USDT);
        uint256 amountIn = TEST_AMOUNT_USDC;
        uint256 slippage = TEST_SLIPPAGE_3_PERCENT;

        uint256 actualAmountOut1 = (TEST_AMOUNT_USDC * 99) / 100;
        TWAP.validateSlippageTWAP(path, amountIn, actualAmountOut1, slippage, ROUTER);

        uint256 actualAmountOut2 = (TEST_AMOUNT_USDC * 105) / 100;
        vm.expectRevert(TWAP.SlippageExceeded.selector);
        this.callValidateSlippageTWAP(path, amountIn, actualAmountOut2, slippage);

        uint256 actualAmountOut3 = (TEST_AMOUNT_USDC * 96) / 100;
        vm.expectRevert(TWAP.SlippageExceeded.selector);
        this.callValidateSlippageTWAP(path, amountIn, actualAmountOut3, slippage);
    }

    function testValidateSlippageTWAPThreeHop() public {
        bytes memory path = abi.encodePacked(USDC, FEE_MEDIUM, WETH, FEE_LOW, USDT, FEE_MEDIUM, WETH);
        uint256 amountIn = TEST_AMOUNT_USDC;
        uint256 slippage = TEST_SLIPPAGE_3_PERCENT;

        uint256 actualAmountOut1 = 0.99 ether;
        TWAP.validateSlippageTWAP(path, amountIn, actualAmountOut1, slippage, ROUTER);

        uint256 actualAmountOut2 = 1.05 ether;
        vm.expectRevert(TWAP.SlippageExceeded.selector);
        this.callValidateSlippageTWAP(path, amountIn, actualAmountOut2, slippage);

        uint256 actualAmountOut3 = 0.93 ether;
        vm.expectRevert(TWAP.SlippageExceeded.selector);
        this.callValidateSlippageTWAP(path, amountIn, actualAmountOut3, slippage);
    }
}
