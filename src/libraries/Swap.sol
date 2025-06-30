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

        // extract the last 20 bytes (tokenOut) from the path and ensure it is USDT
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

        // extract the first 20 bytes (tokenIn) from the path and ensure it is USDT
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

    // todo: getters
}
