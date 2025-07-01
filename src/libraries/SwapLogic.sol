// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title SwapLogic
/// @dev Library for swapping assets
library SwapLogic {
    // solhint-disable-next-line gas-struct-packing
    struct SwapLogicConfig {
        address[1] router;
        address[1] usdt;
        address[1] sxt;
        bytes defaultTargetAssetPath;
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
        _swapLogicConfig.router[0] = newConfig.router[0];
        _swapLogicConfig.usdt[0] = newConfig.usdt[0];
        _swapLogicConfig.sxt[0] = newConfig.sxt[0];
        _swapLogicConfig.defaultTargetAssetPath = newConfig.defaultTargetAssetPath;
    }

    /// @notice get the config for the swap logic
    function getConfig(SwapLogicConfig storage _swapLogicConfig) internal pure returns (SwapLogicConfig memory) {
        return _swapLogicConfig;
    }

    /// @notice validate the path
    function isValidPath(bytes memory path) internal pure returns (bool) {
        // (20 + (3 + 20) * n)
        return path.length == 20 || (path.length - 20) % 23 == 0;
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

        address tokenOut;
        assembly {
            tokenOut := shr(96, calldataload(add(path.offset, sub(path.length, 20))))
        }

        if (tokenOut != _swapLogicConfig.usdt[0]) {
            revert PathMustEndWithUSDT();
        }

        if (tokenOut == address(0)) {
            revert ZeroAddress();
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

        address tokenIn;
        assembly {
            tokenIn := shr(96, calldataload(path.offset))
        }

        if (tokenIn != _swapLogicConfig.usdt[0]) {
            revert PathMustStartWithUSDT();
        }

        if (tokenIn == address(0)) {
            revert ZeroAddress();
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

    /// @notice extract the target asset for the merchant from the path
    /// @param path the swap path
    /// @return targetAsset the target asset
    function getMercahntTargteAsset(bytes memory path) internal pure returns (address targetAsset) {
        address tokenOut;
        assembly {
            let len := mload(path)
            tokenOut := shr(96, mload(add(add(path, 0x20), sub(len, 20))))
        }
        return tokenOut;
    }
}
