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
    function setConfig(SwapLogicConfig storage _swapLogicConfig, SwapLogicConfig calldata newConfig) internal {
        if (newConfig.router == address(0) || newConfig.usdt == address(0)) {
            revert ZeroAddress();
        }

        _swapLogicConfig.router = newConfig.router;
        _swapLogicConfig.usdt = newConfig.usdt;
        _swapLogicConfig.defaultTargetAssetPath = newConfig.defaultTargetAssetPath;
    }

    /// @notice get the config for the swap logic
    function getConfig(SwapLogicConfig storage _swapLogicConfig) internal pure returns (SwapLogicConfig memory) {
        return _swapLogicConfig;
    }

    /// @notice validate the path
    /// @dev valid path is either 20 bytes (single asset) or (20 + 3) * n bytes (multiple assets)
    /// there should be N asset addresses + (N-1) path fees
    /// @param path the swap path
    /// @return valid true if the path is valid, false otherwise
    function isValidPath(bytes memory path) internal pure returns (bool valid) {
        uint256 len = path.length;
        valid = len == 20 || (len >= 43 && (len - 43) % 23 == 0);
    }

    /// @notice extract the destination asset from the path
    /// @param path the swap path
    /// @return tokenOut the destination asset
    function callbackExtractPathDestinationAsset(bytes calldata path) internal pure returns (address tokenOut) {
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
    function extractPathOriginAsset(bytes calldata path) internal pure returns (address tokenIn) {
        assembly {
            tokenIn := shr(ADDRESS_OFFSET_BITS, calldataload(path.offset))
        }
    }

    /// @notice set the path for the source asset
    function setSourceAssetPath(
        mapping(address asset => bytes sourceAssetPath) storage _sourceAssetsPaths,
        SwapLogicConfig storage _swapLogicConfig,
        address sourceAsset,
        bytes calldata path
    ) internal {
        if (!isValidPath(path)) {
            revert InvalidPath();
        }

        address tokenOut = callbackExtractPathDestinationAsset(path);

        if (tokenOut != _swapLogicConfig.usdt) {
            revert PathMustEndWithUSDT();
        }

        _sourceAssetsPaths[sourceAsset] = path;
        emit SourceAssetPathSet(sourceAsset, path);
    }

    /// @notice set the path for the target asset
    function setMerchantTargetAssetPath(
        mapping(address merchant => bytes targetAssetPath) storage _merchantTargetAssetsPaths,
        SwapLogicConfig storage _swapLogicConfig,
        address merchant,
        bytes calldata path
    ) internal {
        if (!isValidPath(path)) {
            revert InvalidPath();
        }

        address tokenIn = extractPathOriginAsset(path);

        if (tokenIn != _swapLogicConfig.usdt) {
            revert PathMustStartWithUSDT();
        }

        _merchantTargetAssetsPaths[merchant] = path;
        emit MerchantTargetAssetPathSet(merchant, path);
    }

    /// @notice get the path for the source asset which is used to swap the source asset to the USDT token
    /// @param _sourceAssetsPaths the mapping of source assets to their paths
    /// @param sourceAsset the address of the source asset
    /// @return the path for the source asset
    function getSourceAssetPath(
        mapping(address asset => bytes sourceAssetPath) storage _sourceAssetsPaths,
        address sourceAsset
    ) internal view returns (bytes storage) {
        return _sourceAssetsPaths[sourceAsset];
    }

    /// @notice get the path for the target asset which is used to swap the USDT token to the target asset
    /// @param _merchantTargetAssetsPaths the mapping of merchants to their target asset paths
    /// @param merchant the address of the merchant
    /// @return the path for the target asset
    function getMerchantTargetAssetPath(
        mapping(address merchant => bytes targetAssetPath) storage _merchantTargetAssetsPaths,
        address merchant
    ) internal view returns (bytes storage) {
        return _merchantTargetAssetsPaths[merchant];
    }
}
