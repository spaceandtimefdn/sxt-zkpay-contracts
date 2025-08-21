// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {ZERO_ADDRESS} from "./Constants.sol";

/// @title SwapLogic
/// @dev Library for swapping assets
library SwapLogic {
    using SafeERC20 for IERC20;

    uint256 internal constant WORD_SIZE = 0x20;
    uint256 internal constant FREE_PTR = 0x40;
    uint256 internal constant ADDRESS_SIZE = 20;
    uint256 internal constant ADDRESS_OFFSET_BITS = 96;
    uint256 internal constant PATH_FEED_SIZE = 3;
    uint256 internal constant MIN_AMOUNT_OUT = 0;

    // solhint-disable-next-line gas-struct-packing
    struct SwapLogicConfig {
        address router;
        address usdt;
    }

    struct AssetSwapPaths {
        mapping(address asset => bytes sourceAssetPath) sourceAssetPaths;
        mapping(address merchant => bytes targetAssetPath) merchantTargetAssetPaths;
    }

    struct SwapLogicStorage {
        SwapLogicConfig swapLogicConfig;
        AssetSwapPaths assetSwapPaths;
    }

    /// @notice Error thrown when the provided swap path bytes are not a valid Uniswap V3 path encoding
    error InvalidPath();
    /// @notice Error thrown when the swap path does not end with the USDT token defined in the contract config
    error PathMustEndWithUSDT();
    /// @notice Error thrown when the swap path does not start with the USDT token defined in the contract config
    error PathMustStartWithUSDT();
    /// @notice Error thrown when the provided address is the zero address
    error ZeroAddress();
    /// @notice Error thrown when the paths do not connect
    error PathsDoNotConnect();

    /// @notice Emitted when a source asset path is set by admin
    event SourceAssetPathSet(address indexed asset, bytes path);
    /// @notice Emitted when a merchant target asset path is set by merchant
    event MerchantTargetAssetPathSet(address indexed merchant, bytes path);

    /// @notice set the essential config for swaps
    function setConfig(SwapLogicStorage storage _swapLogicStorage, SwapLogicConfig memory newConfig) internal {
        if (newConfig.router == ZERO_ADDRESS || newConfig.usdt == ZERO_ADDRESS) {
            revert ZeroAddress();
        }

        _swapLogicStorage.swapLogicConfig = newConfig;
    }

    /// @notice get the config for the swap logic
    function getConfig(SwapLogicStorage storage _swapLogicStorage) internal view returns (SwapLogicConfig memory) {
        return _swapLogicStorage.swapLogicConfig;
    }

    /// @notice validate the path
    /// @dev valid path is either 20 bytes (single asset) or (20 + 3) * n bytes (multiple assets)
    /// there should be N asset addresses + (N-1) path fees
    /// @param path the swap path
    /// @return valid true if the path is valid, false otherwise
    function isValidPath(bytes memory path) internal pure returns (bool valid) {
        valid = path.length % 23 == 20;
    }

    /// @notice extract the destination asset from the path
    /// @param path the swap path
    /// @return tokenOut the destination asset
    function calldataExtractPathDestinationAsset(bytes calldata path) internal pure returns (address tokenOut) {
        assembly {
            tokenOut := shr(ADDRESS_OFFSET_BITS, calldataload(add(path.offset, sub(path.length, ADDRESS_SIZE))))
        }
    }

    /// @notice extract the destination asset from the path
    /// @param path the swap path
    /// @return tokenOut the destination asset
    /// @dev this function assumes the path is valid and does not check for it. use isValidPath to check for validity
    function extractPathDestinationAsset(bytes memory path) internal pure returns (address tokenOut) {
        assembly {
            let len := mload(path)
            tokenOut := shr(ADDRESS_OFFSET_BITS, mload(add(add(path, WORD_SIZE), sub(len, ADDRESS_SIZE))))
        }
    }

    /// @notice extract the origin asset from the path
    /// @param path the swap path
    /// @return tokenIn the source asset
    /// @dev this function assumes the path is valid and does not check for it. use isValidPath to check for validity
    function extractPathOriginAsset(bytes memory path) internal pure returns (address tokenIn) {
        assembly {
            tokenIn := shr(ADDRESS_OFFSET_BITS, mload(add(path, 0x20)))
        }
    }

    /// @notice extract the origin asset from the path
    /// @param path the swap path
    /// @return tokenIn the source asset
    /// @dev this function assumes the path is valid and does not check for it. use isValidPath to check for validity
    function calldataExtractPathOriginAsset(bytes calldata path) internal pure returns (address tokenIn) {
        assembly {
            tokenIn := shr(ADDRESS_OFFSET_BITS, calldataload(path.offset))
        }
    }

    /// @notice set the path for the source asset
    function setSourceAssetPath(SwapLogicStorage storage _swapLogicStorage, bytes calldata path) internal {
        if (!isValidPath(path)) {
            revert InvalidPath();
        }

        address tokenOut = calldataExtractPathDestinationAsset(path);

        if (tokenOut != _swapLogicStorage.swapLogicConfig.usdt) {
            revert PathMustEndWithUSDT();
        }

        address sourceAsset = calldataExtractPathOriginAsset(path);

        _swapLogicStorage.assetSwapPaths.sourceAssetPaths[sourceAsset] = path;
        emit SourceAssetPathSet(sourceAsset, path);
    }

    /// @notice set the path for the target asset
    function setMerchantTargetAssetPath(
        SwapLogicStorage storage _swapLogicStorage,
        address merchant,
        bytes calldata path
    ) internal {
        if (!isValidPath(path)) {
            revert InvalidPath();
        }

        address tokenIn = calldataExtractPathOriginAsset(path);

        if (tokenIn != _swapLogicStorage.swapLogicConfig.usdt) {
            revert PathMustStartWithUSDT();
        }

        _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[merchant] = path;
        emit MerchantTargetAssetPathSet(merchant, path);
    }

    /// @notice get the path for the source asset which is used to swap the source asset to the USDT token
    /// @param _swapLogicStorage the storage of the swap logic
    /// @param sourceAsset the address of the source asset
    /// @return the path for the source asset
    function getSourceAssetPath(SwapLogicStorage storage _swapLogicStorage, address sourceAsset)
        internal
        view
        returns (bytes storage)
    {
        return _swapLogicStorage.assetSwapPaths.sourceAssetPaths[sourceAsset];
    }

    /// @notice get the path for the target asset which is used to swap the USDT token to the target asset
    /// @param _swapLogicStorage the storage of the swap logic
    /// @param merchant the address of the merchant
    /// @return the path for the target asset
    function getMerchantTargetAssetPath(SwapLogicStorage storage _swapLogicStorage, address merchant)
        internal
        view
        returns (bytes storage)
    {
        return _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[merchant];
    }

    /// @notice get the payout asset address for a merchant by extracting it from their target asset path
    /// @param _swapLogicStorage the storage of the swap logic
    /// @param merchant the address of the merchant
    /// @return payoutAsset the address of the merchant's payout asset
    function getMerchantPayoutAsset(SwapLogicStorage storage _swapLogicStorage, address merchant)
        internal
        view
        returns (address payoutAsset)
    {
        bytes storage targetAssetPath = _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[merchant];
        payoutAsset = extractPathDestinationAsset(targetAssetPath);
    }

    /// @notice connect two paths (path1 -> path2)
    /// @param path1 the first path
    /// @param path2 the second path
    /// @return result the connected path
    /// @dev this function assumes the paths are valid and does not check for it for better gas performance. use isValidPath to check for validity
    function _connect2Paths(bytes memory path1, bytes memory path2) internal pure returns (bytes memory result) {
        address firstPathTokenOut = extractPathDestinationAsset(path1);
        address secondPathTokenIn = extractPathOriginAsset(path2);

        if (firstPathTokenOut != secondPathTokenIn) {
            revert PathsDoNotConnect();
        }

        uint256 path1Len = path1.length - ADDRESS_SIZE;
        uint256 path2Len = path2.length;
        result = new bytes(path1Len + path2Len);

        assembly {
            let resultPtr := add(result, WORD_SIZE)
            let path1Ptr := add(path1, WORD_SIZE)
            let path2Ptr := add(path2, WORD_SIZE)
            mcopy(resultPtr, path1Ptr, path1Len)
            mcopy(add(resultPtr, path1Len), path2Ptr, path2Len)
        }
    }

    /// @notice does swap with uniswap v3 router using exact input amount
    /// @param router the uniswap v3 router address
    /// @param path the path to swap
    /// @param amountIn the amount of the source asset to swap
    /// @param recipient the recipient of the destination asset
    /// @return amountOut the amount of the destination asset received
    /// @dev this function assumes the path is >= 1 hop valid path, make sure validate the path before calling this function
    /// @dev the contract that implements this library should hold `amountIn` of the source asset
    function _swapExactAmountIn(address router, bytes memory path, uint256 amountIn, address recipient)
        internal
        returns (uint256 amountOut)
    {
        address tokenIn = extractPathOriginAsset(path);
        IERC20(tokenIn).safeIncreaseAllowance(router, amountIn);
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams(path, recipient, block.timestamp, amountIn, MIN_AMOUNT_OUT);
        amountOut = ISwapRouter(router).exactInput(params);
    }

    /// @notice Swaps source asset to merchant target asset using exact source amount, returns swap results without handling transfers
    /// @param _swapLogicStorage the storage of the swap logic
    /// @param sourceAsset the source asset to swap from
    /// @param merchant the merchant address to get target asset path
    /// @param targetAssetRecipient the recipient of the target asset
    /// @return receivedTargetAssetAmount the amount of received target asset tokens from the swapping router
    function swapExactSourceAssetAmount(
        SwapLogicStorage storage _swapLogicStorage,
        address sourceAsset,
        address merchant,
        uint256 sourceAssetAmountIn,
        address targetAssetRecipient,
        bytes memory customSourceAssetPath
    ) internal returns (uint256 receivedTargetAssetAmount) {
        bytes memory swapPath;
        if (customSourceAssetPath.length > 0) {
            swapPath = _connect2Paths(
                customSourceAssetPath, _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[merchant]
            );
        } else {
            swapPath = _connect2Paths(
                _swapLogicStorage.assetSwapPaths.sourceAssetPaths[sourceAsset],
                _swapLogicStorage.assetSwapPaths.merchantTargetAssetPaths[merchant]
            );
        }

        receivedTargetAssetAmount = _swapExactAmountIn(
            _swapLogicStorage.swapLogicConfig.router, swapPath, sourceAssetAmountIn, targetAssetRecipient
        );
    }
}
