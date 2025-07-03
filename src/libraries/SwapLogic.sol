// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title SwapLogic
/// @dev Library for swapping assets
library SwapLogic {
    uint256 internal constant WORD_SIZE = 0x20;
    uint256 internal constant ADDRESS_SIZE = 20;
    uint256 internal constant ADDRESS_OFFSET_BITS = 96;
    uint256 internal constant PATH_FEED_SIZE = 3;

    // solhint-disable-next-line gas-struct-packing
    struct SwapLogicConfig {
        address router;
        address usdt;
        bytes defaultTargetAssetPath;
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

    /// @notice Emitted when a source asset path is set by owner
    event SourceAssetPathSet(address indexed asset, bytes path);
    /// @notice Emitted when a merchant target asset path is set by merchant
    event MerchantTargetAssetPathSet(address indexed merchant, bytes path);

    /// @notice set the essential config for swaps
    function setConfig(SwapLogicStorage storage _swapLogicStorage, SwapLogicConfig calldata newConfig) internal {
        if (newConfig.router == address(0) || newConfig.usdt == address(0)) {
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
}
