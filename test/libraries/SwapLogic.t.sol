// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SwapLogic} from "../../src/libraries/SwapLogic.sol";

contract SwapLogicTest is Test {
    SwapLogic.SwapLogicConfig internal _swapLogicConfig;
    mapping(address => bytes) internal _sourceAssetPaths;
    mapping(address => bytes) internal _merchantTargetAssetPaths;

    address internal constant ROUTER = address(0x1111);
    address internal constant USDT = address(0x2222);
    address internal constant SXT = address(0x3333);
    address internal constant SOURCE_ASSET = address(0xAAAA);
    address internal constant MERCHANT = address(0xBBBB);

    function setUp() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router[0] = ROUTER;
        cfg.usdt[0] = USDT;
        cfg.sxt[0] = SXT;
        cfg.defaultTargetAssetPath = abi.encodePacked(USDT);
        this._setConfig(cfg);
    }

    function _setConfig(SwapLogic.SwapLogicConfig calldata cfg) external {
        SwapLogic.setConfig(_swapLogicConfig, cfg);
    }

    function _setSourceAssetPath(address asset, bytes calldata path) external {
        SwapLogic.setSourceAssetPath(_sourceAssetPaths, _swapLogicConfig, asset, path);
    }

    function _setMerchantTargetAssetPath(address merchant, bytes calldata path) external {
        SwapLogic.setMerchantTargetAssetPath(_merchantTargetAssetPaths, _swapLogicConfig, merchant, path);
    }

    function testSetAndGetConfig() public view {
        SwapLogic.SwapLogicConfig memory cfg = SwapLogic.getConfig(_swapLogicConfig);
        assertEq(cfg.router[0], ROUTER, "router addr mismatch");
        assertEq(cfg.usdt[0], USDT, "usdt addr mismatch");
        assertEq(cfg.sxt[0], SXT, "sxt addr mismatch");
        assertEq(keccak256(cfg.defaultTargetAssetPath), keccak256(abi.encodePacked(USDT)), "default path mismatch");
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
        bytes memory path = abi.encodePacked(USDT);

        vm.expectEmit(true, false, false, true);
        emit SwapLogic.SourceAssetPathSet(SOURCE_ASSET, path);
        this._setSourceAssetPath(SOURCE_ASSET, path);

        assertEq(keccak256(_sourceAssetPaths[SOURCE_ASSET]), keccak256(path));
    }

    function testSetSourceAssetPathInvalidPathReverts() public {
        bytes memory badPath = new bytes(21);
        vm.expectRevert(SwapLogic.InvalidPath.selector);
        this._setSourceAssetPath(SOURCE_ASSET, badPath);
    }

    function testSetSourceAssetPathWrongTokenOutReverts() public {
        bytes memory wrongPath = abi.encodePacked(address(0xDEAD)); // ends with wrong token
        vm.expectRevert(SwapLogic.PathMustEndWithUSDT.selector);
        this._setSourceAssetPath(SOURCE_ASSET, wrongPath);
    }

    function testSetSourceAssetPathZeroAddressReverts() public {
        SwapLogic.SwapLogicConfig memory cfg;
        cfg.router[0] = ROUTER;
        cfg.usdt[0] = address(0);
        cfg.sxt[0] = SXT;
        cfg.defaultTargetAssetPath = bytes("");
        this._setConfig(cfg);

        bytes memory zeroPath = abi.encodePacked(address(0));
        vm.expectRevert(SwapLogic.ZeroAddress.selector);
        this._setSourceAssetPath(SOURCE_ASSET, zeroPath);
    }

    function testSetMerchantTargetAssetPath() public {
        bytes memory path = abi.encodePacked(USDT);

        vm.expectEmit(true, false, false, true);
        emit SwapLogic.MerchantTargetAssetPathSet(MERCHANT, path);
        this._setMerchantTargetAssetPath(MERCHANT, path);

        assertEq(keccak256(_merchantTargetAssetPaths[MERCHANT]), keccak256(path));
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
        cfg.router[0] = ROUTER;
        cfg.usdt[0] = address(0);
        cfg.sxt[0] = SXT;
        cfg.defaultTargetAssetPath = bytes("");
        this._setConfig(cfg);

        bytes memory zeroPath = abi.encodePacked(address(0));
        vm.expectRevert(SwapLogic.ZeroAddress.selector);
        this._setMerchantTargetAssetPath(MERCHANT, zeroPath);
    }

    function testGetMercahntTargteAsset() public pure {
        bytes memory path = abi.encodePacked(USDT);
        assertEq(SwapLogic.getMercahntTargteAsset(path), USDT);
    }

    function testGetSourceAssetPath() public {
        bytes memory path = abi.encodePacked(USDT);
        this._setSourceAssetPath(SOURCE_ASSET, path);
        assertEq(keccak256(SwapLogic.getSourceAssetPath(_sourceAssetPaths, SOURCE_ASSET)), keccak256(path));
    }

    function testGetMerchantTargetAssetPath() public {
        bytes memory path = abi.encodePacked(USDT);
        this._setMerchantTargetAssetPath(MERCHANT, path);
        assertEq(keccak256(SwapLogic.getMerchantTargetAssetPath(_merchantTargetAssetPaths, MERCHANT)), keccak256(path));
    }
}
