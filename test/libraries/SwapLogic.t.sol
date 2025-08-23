// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SwapLogic} from "../../src/libraries/SwapLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";
import {RPC_URL, ROUTER, USDT, SXT, USDC, BLOCK_NUMBER} from "../data/MainnetConstants.sol";

contract SwapLogicTest is Test {
    SwapLogic.SwapLogicStorage internal _swapLogicStorage;

    address internal constant SOURCE_ASSET = address(0xAAAA);
    address internal constant MERCHANT = address(0xBBBB);

    SwapLogicWrapper internal wrapper;

    function setUp() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ROUTER;
        cfg.usdt = USDT;
        this._setConfig(cfg);
        wrapper = new SwapLogicWrapper();
    }

    function _setConfig(SwapLogic.SwapLogicConfig calldata cfg) external {
        SwapLogic.setConfig(_swapLogicStorage, cfg);
    }

    function _setSourceAssetPath(bytes calldata path) external {
        SwapLogic.setSourceAssetPath(_swapLogicStorage, path);
    }

    function _setMerchantTargetAssetPath(address merchant, bytes calldata path) external {
        SwapLogic.setMerchantTargetAssetPath(_swapLogicStorage, merchant, path);
    }

    function testSetAndGetConfig() public view {
        SwapLogic.SwapLogicConfig memory cfg = SwapLogic.getConfig(_swapLogicStorage);
        assertEq(cfg.router, ROUTER, "router addr mismatch");
        assertEq(cfg.usdt, USDT, "usdt addr mismatch");
    }

    function testSetConfigRouterZeroAddressReverts() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ZERO_ADDRESS;
        cfg.usdt = USDT;
        vm.expectRevert(SwapLogic.ZeroAddress.selector);
        this._setConfig(cfg);
    }

    function testSetConfigUsdtZeroAddressReverts() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ROUTER;
        cfg.usdt = ZERO_ADDRESS;
        vm.expectRevert(SwapLogic.ZeroAddress.selector);
        this._setConfig(cfg);
    }

    function testFuzzIsValidPath(bytes memory path) public pure {
        uint256 addressSize = 20;
        uint256 pathFeeSize = 3;
        uint256 path1HopLength = addressSize + pathFeeSize + addressSize;

        if (path.length < addressSize) {
            // < 20 bytes
            assertFalse(SwapLogic.isValidPath(path));
        } else if (path.length == addressSize) {
            // 20 bytes
            assertTrue(SwapLogic.isValidPath(path));
        } else if (path.length < path1HopLength) {
            // < 43 bytes
            assertFalse(SwapLogic.isValidPath(path));
        } else {
            // 43 and more bytes
            uint256 lengthWithoutFirstAddress = path.length - addressSize;
            // should be valid if lengthWithoutFirstAddress is divisible by (addressSize + pathFeeSize)
            if (lengthWithoutFirstAddress % (addressSize + pathFeeSize) == 0) {
                assertTrue(SwapLogic.isValidPath(path));
            } else {
                assertFalse(SwapLogic.isValidPath(path));
            }
        }
    }

    function testIsValidPathLength20() public pure {
        bytes memory path = abi.encodePacked(USDT);
        assertTrue(SwapLogic.isValidPath(path));
    }

    function testIsValidPath2Hops() public pure {
        address tokenIn = address(0x1234);
        bytes memory path = abi.encodePacked(tokenIn, uint24(3000), USDT);
        assertEq(path.length, 43, "path length should be 43 bytes");
        assertTrue(SwapLogic.isValidPath(path));
    }

    function testIsValidPathInvalid() public pure {
        bytes memory badPath = new bytes(21); // invalid length
        assertFalse(SwapLogic.isValidPath(badPath));
    }

    function testSetSourceAssetPath() public {
        bytes memory path = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), USDT);

        vm.expectEmit(true, false, false, true);
        emit SwapLogic.SourceAssetPathSet(SOURCE_ASSET, path);
        this._setSourceAssetPath(path);

        assertEq(keccak256(SwapLogic.getSourceAssetPath(_swapLogicStorage, SOURCE_ASSET)), keccak256(path));
    }

    function testSetSourceAssetPathInvalidPathReverts() public {
        bytes memory badPath = new bytes(21);
        vm.expectRevert(SwapLogic.InvalidPath.selector);
        this._setSourceAssetPath(badPath);
    }

    function testSetSourceAssetPathWrongTokenOutReverts() public {
        bytes memory wrongPath = abi.encodePacked(address(0xDEAD)); // ends with wrong token
        vm.expectRevert(SwapLogic.PathMustEndWithUSDT.selector);
        this._setSourceAssetPath(wrongPath);
    }

    function testSetSourceAssetPathZeroAddressReverts() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ROUTER;
        cfg.usdt = address(0x1234);
        this._setConfig(cfg);

        bytes memory zeroPath = abi.encodePacked(ZERO_ADDRESS);
        vm.expectRevert(SwapLogic.PathMustEndWithUSDT.selector);
        this._setSourceAssetPath(zeroPath);
    }

    function testSetMerchantTargetAssetPath() public {
        bytes memory path = abi.encodePacked(USDT);

        vm.expectEmit(true, false, false, true);
        emit SwapLogic.MerchantTargetAssetPathSet(MERCHANT, path);
        this._setMerchantTargetAssetPath(MERCHANT, path);

        assertEq(keccak256(SwapLogic.getMerchantTargetAssetPath(_swapLogicStorage, MERCHANT)), keccak256(path));
    }

    function testSetMerchantTargetAssetPathInvalidPathReverts() public {
        bytes memory badPath = new bytes(21);
        vm.expectRevert(SwapLogic.InvalidPath.selector);
        this._setMerchantTargetAssetPath(MERCHANT, badPath);
    }

    function testSetMerchantTargetAssetPathWrongTokenInReverts() public {
        bytes memory wrongPath = abi.encodePacked(address(0xDEAD));
        vm.expectRevert(SwapLogic.PathMustStartWithUSDT.selector);
        this._setMerchantTargetAssetPath(MERCHANT, wrongPath);
    }

    function testSetMerchantTargetAssetPathZeroAddressReverts() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ROUTER;
        cfg.usdt = address(0x1234);
        this._setConfig(cfg);

        bytes memory zeroPath = abi.encodePacked(ZERO_ADDRESS);
        vm.expectRevert(SwapLogic.PathMustStartWithUSDT.selector);
        this._setMerchantTargetAssetPath(MERCHANT, zeroPath);
    }

    function testGetMercahntTargteAsset() public pure {
        bytes memory path = abi.encodePacked(USDT);
        assertEq(SwapLogic.extractPathDestinationAsset(path), USDT);
    }

    function testExtractPathOriginAsset() public pure {
        bytes memory path = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), USDT);
        assertEq(SwapLogic.extractPathOriginAsset(path), SOURCE_ASSET);
    }

    function testGetSourceAssetPath() public {
        bytes memory path = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), USDT);
        this._setSourceAssetPath(path);
        assertEq(keccak256(SwapLogic.getSourceAssetPath(_swapLogicStorage, SOURCE_ASSET)), keccak256(path));
    }

    function testGetMerchantTargetAssetPath() public {
        bytes memory path = abi.encodePacked(USDT);
        this._setMerchantTargetAssetPath(MERCHANT, path);
        assertEq(keccak256(SwapLogic.getMerchantTargetAssetPath(_swapLogicStorage, MERCHANT)), keccak256(path));
    }

    function testCalldataExtractPathDestinationAssetAddress() public view {
        bytes memory path = abi.encodePacked(SOURCE_ASSET);
        assertEq(wrapper.calldataExtractPathDestinationAsset(path), SOURCE_ASSET);
    }

    function testCalldataExtractPathDestinationAsset1Hop() public view {
        bytes memory path = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), USDT);
        assertEq(wrapper.calldataExtractPathDestinationAsset(path), USDT);
    }

    function testCalldataExtractPathDestinationAsset2Hop() public view {
        bytes memory path = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), address(0x4444), bytes3(0x102030), USDT);
        assertEq(wrapper.calldataExtractPathDestinationAsset(path), USDT);
    }

    function testCalldataExtractPathOriginAsset() public view {
        bytes memory path = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), USDT);
        assertEq(wrapper.calldataExtractPathOriginAsset(path), SOURCE_ASSET);
    }

    function testConnect2Paths() public pure {
        address destinationAsset = address(0x4444);

        bytes memory sourcePath = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), USDT); // source -> USDT; 43 bytes
        bytes memory destinationPath = abi.encodePacked(USDT, bytes3(0x102030), destinationAsset); // USDT -> destination; 43 bytes
        bytes memory result = SwapLogic._connect2Paths(sourcePath, destinationPath); // source -> USDT -> destination; 66 bytes

        assertEq(result.length, 66);
        assertEq(SwapLogic.extractPathOriginAsset(result), SOURCE_ASSET);
        assertEq(SwapLogic.extractPathDestinationAsset(result), destinationAsset);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testConnect2PathsPathsDoNotConnect() public {
        bytes memory path1 = abi.encodePacked(SOURCE_ASSET);
        bytes memory path2 = abi.encodePacked(address(0xDEAD));
        vm.expectRevert(SwapLogic.PathsDoNotConnect.selector);
        SwapLogic._connect2Paths(path1, path2);
    }

    function testConnect2PathsBothSingleAsset() public pure {
        bytes memory path1 = abi.encodePacked(SOURCE_ASSET);
        bytes memory path2 = abi.encodePacked(SOURCE_ASSET);
        bytes memory result = SwapLogic._connect2Paths(path1, path2);
        assertEq(result, path1);
    }

    function testConnect2PathsFirstSingleAsset() public pure {
        address destinationAsset = address(0x4444);
        bytes memory path1 = abi.encodePacked(USDT);
        bytes memory path2 = abi.encodePacked(USDT, bytes3(0x102030), destinationAsset);
        bytes memory result = SwapLogic._connect2Paths(path1, path2);
        assertEq(result, path2);
    }

    function testConnect2PathsSecondSingleAsset() public pure {
        bytes memory path1 = abi.encodePacked(SOURCE_ASSET, bytes3(0x112233), USDT);
        bytes memory path2 = abi.encodePacked(USDT);
        bytes memory result = SwapLogic._connect2Paths(path1, path2);
        assertEq(result, path1);
    }

    function testGetMerchantPayoutAsset() public {
        address payoutAsset = address(0x5555);
        bytes memory merchantPath = abi.encodePacked(USDT, bytes3(0x102030), payoutAsset);

        this._setMerchantTargetAssetPath(MERCHANT, merchantPath);

        address retrievedPayoutAsset = SwapLogic.getMerchantPayoutAsset(_swapLogicStorage, MERCHANT);
        assertEq(retrievedPayoutAsset, payoutAsset);
    }
}

contract SwapLogicWrapper {
    SwapLogic.SwapLogicStorage internal _swapLogicStorage;

    constructor() {
        // source paths
        _swapLogicStorage.assetSwapPaths.sourceAssetPaths[SXT] = abi.encodePacked(SXT, bytes3(uint24(3000)), USDT);

        // destination paths
        _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[USDT] =
            abi.encodePacked(USDT, bytes3(uint24(3000)), USDC);

        _swapLogicStorage.swapLogicConfig = SwapLogic.SwapLogicConfig({router: ROUTER, usdt: USDT});
    }

    function _swapExactAmountIn(bytes memory path, uint256 amountIn, address recipient)
        public
        returns (uint256 amountOut)
    {
        return SwapLogic._swapExactAmountIn(ROUTER, path, amountIn, recipient);
    }

    function calldataExtractPathDestinationAsset(bytes calldata path) external pure returns (address) {
        return SwapLogic.calldataExtractPathDestinationAsset(path);
    }

    function calldataExtractPathOriginAsset(bytes calldata path) external pure returns (address) {
        return SwapLogic.calldataExtractPathOriginAsset(path);
    }

    function setSourceAssetPath(address sourceAsset, bytes calldata path) external {
        _swapLogicStorage.assetSwapPaths.sourceAssetPaths[sourceAsset] = path;
    }

    function setMerchantTargetAssetPath(address merchant, bytes calldata path) external {
        _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[merchant] = path;
    }

    function swapExactSourceAssetAmount(
        address sourceAsset,
        address merchant,
        uint256 sourceAssetAmountIn,
        address targetAssetRecipient
    ) external returns (uint256 receivedTargetAssetAmount) {
        return SwapLogic.swapExactSourceAssetAmount(
            _swapLogicStorage, sourceAsset, merchant, sourceAssetAmountIn, targetAssetRecipient, ""
        );
    }
}

contract SwapLogicSwapTest is Test {
    SwapLogicWrapper internal wrapper;

    function setUp() public {
        vm.createSelectFork(RPC_URL, BLOCK_NUMBER);
        wrapper = new SwapLogicWrapper();
    }

    function testSwapSXTtoUSDT() public {
        bytes memory path = abi.encodePacked(SXT, bytes3(uint24(3000)), USDT);

        uint256 amountIn = 100e18; // 100 SXT
        address recipient = address(0x1234);

        // deal wrapper amountIn of sxt
        deal(SXT, address(wrapper), amountIn);

        uint256 amountOut = wrapper._swapExactAmountIn(path, amountIn, recipient);
        assertGt(IERC20(USDT).balanceOf(recipient), 0);
        assertEq(IERC20(USDT).balanceOf(recipient), amountOut);
    }

    // SXT -> USDT -> USDC
    function testSwapSXTtoUSDTtoUSDC() public {
        bytes memory path = abi.encodePacked(SXT, bytes3(uint24(3000)), USDT, bytes3(uint24(3000)), USDC);

        uint256 amountIn = 100e18; // 100 SXT
        address recipient = address(0x1234);

        // deal wrapper amountIn of sxt
        deal(SXT, address(wrapper), amountIn);

        uint256 amountOut = wrapper._swapExactAmountIn(path, amountIn, recipient);
        assertGt(IERC20(USDC).balanceOf(recipient), 0);
        assertEq(IERC20(USDC).balanceOf(recipient), amountOut);
    }

    function testSwapExactSourceAssetAmount() public {
        address merchant = address(0x1234);
        address sourceAsset = SXT;
        address targetAsset = USDC;
        wrapper.setSourceAssetPath(sourceAsset, abi.encodePacked(sourceAsset, bytes3(uint24(3000)), USDT));
        wrapper.setMerchantTargetAssetPath(merchant, abi.encodePacked(USDT, bytes3(uint24(3000)), targetAsset));

        uint256 amountIn = 100e18; // 100 SXT
        address recipient = address(0x5678);

        assertEq(IERC20(sourceAsset).balanceOf(address(wrapper)), 0);
        deal(sourceAsset, address(wrapper), amountIn);

        uint256 receivedTargetAssetAmount =
            wrapper.swapExactSourceAssetAmount(sourceAsset, merchant, amountIn, recipient);
        assertGt(IERC20(targetAsset).balanceOf(recipient), 0);
        assertEq(IERC20(targetAsset).balanceOf(recipient), receivedTargetAssetAmount);
        assertEq(IERC20(sourceAsset).balanceOf(address(wrapper)), 0);
    }
}
