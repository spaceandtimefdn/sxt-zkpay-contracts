// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SwapLogic} from "../../src/libraries/SwapLogic.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ZERO_ADDRESS} from "../../src/libraries/Constants.sol";

contract SwapLogicTest is Test {
    SwapLogic.SwapLogicStorage internal _swapLogicStorage;

    address internal constant ROUTER = address(0x1111);
    address internal constant USDT = address(0x2222);
    address internal constant SXT = address(0x3333);
    address internal constant SOURCE_ASSET = address(0xAAAA);
    address internal constant MERCHANT = address(0xBBBB);

    SwapLogicWrapper internal wrapper;

    function setUp() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ROUTER;
        cfg.usdt = USDT;
        cfg.defaultTargetAssetPath = abi.encodePacked(USDT);
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
        assertEq(keccak256(cfg.defaultTargetAssetPath), keccak256(abi.encodePacked(USDT)), "default path mismatch");
    }

    function testSetConfigRouterZeroAddressReverts() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ZERO_ADDRESS;
        cfg.usdt = USDT;
        cfg.defaultTargetAssetPath = abi.encodePacked(USDT);
        vm.expectRevert(SwapLogic.ZeroAddress.selector);
        this._setConfig(cfg);
    }

    function testSetConfigUsdtZeroAddressReverts() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router = ROUTER;
        cfg.usdt = ZERO_ADDRESS;
        cfg.defaultTargetAssetPath = abi.encodePacked(USDT);
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
        cfg.defaultTargetAssetPath = bytes("");
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
        cfg.defaultTargetAssetPath = bytes("");
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
}

contract SwapLogicWrapper {
    SwapLogic.SwapLogicStorage internal _swapLogicStorage;

    address public constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant SXT = 0xE6Bfd33F52d82Ccb5b37E16D3dD81f9FFDAbB195;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    constructor() {
        // source paths
        _swapLogicStorage.assetSwapPaths.sourceAssetPaths[SXT] = abi.encodePacked(SXT, bytes3(uint24(3000)), USDT);

        // destination paths
        _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[USDT] =
            abi.encodePacked(USDT, bytes3(uint24(3000)), USDC);

        bytes memory defaultTargetAssetPath = _swapLogicStorage.assetSwapPaths.sourceAssetPaths[SXT];

        _swapLogicStorage.swapLogicConfig =
            SwapLogic.SwapLogicConfig({router: ROUTER, usdt: USDT, defaultTargetAssetPath: defaultTargetAssetPath});
    }

    function swap(bytes memory path, uint256 amountIn, address recipient) public returns (uint256 amountOut) {
        return SwapLogic._swapExactSourceAmount(_swapLogicStorage.swapLogicConfig.router, path, amountIn, recipient);
    }

    function calldataExtractPathDestinationAsset(bytes calldata path) external pure returns (address) {
        return SwapLogic.calldataExtractPathDestinationAsset(path);
    }

    function calldataExtractPathOriginAsset(bytes calldata path) external pure returns (address) {
        return SwapLogic.calldataExtractPathOriginAsset(path);
    }
}

contract SwapLogicSwapTest is Test {
    SwapLogicWrapper internal wrapper;

    function setUp() public {
        // solhint-disable-next-line gas-small-strings
        vm.createSelectFork("https://ethereum-rpc.publicnode.com", 22790000); // mainnet fork
        wrapper = new SwapLogicWrapper();
    }

    function testSwapSXTtoUSDT() public {
        bytes memory path = abi.encodePacked(wrapper.SXT(), bytes3(uint24(3000)), wrapper.USDT());

        uint256 amountIn = 100e18; // 100 SXT
        address recipient = address(0x1234);

        // deal wrapper amountIn of sxt
        deal(wrapper.SXT(), address(wrapper), amountIn);

        uint256 amountOut = wrapper.swap(path, amountIn, recipient);
        assertGt(IERC20(wrapper.USDT()).balanceOf(recipient), 0);
        assertEq(IERC20(wrapper.USDT()).balanceOf(recipient), amountOut);
    }

    // SXT -> USDT -> USDC
    function testSwapSXTtoUSDTtoUSDC() public {
        bytes memory path =
            abi.encodePacked(wrapper.SXT(), bytes3(uint24(3000)), wrapper.USDT(), bytes3(uint24(3000)), wrapper.USDC());

        uint256 amountIn = 100e18; // 100 SXT
        address recipient = address(0x1234);

        // deal wrapper amountIn of sxt
        deal(wrapper.SXT(), address(wrapper), amountIn);

        uint256 amountOut = wrapper.swap(path, amountIn, recipient);
        assertGt(IERC20(wrapper.USDC()).balanceOf(recipient), 0);
        assertEq(IERC20(wrapper.USDC()).balanceOf(recipient), amountOut);
    }
}
