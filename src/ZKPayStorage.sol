// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "./libraries/AssetManagement.sol";
import {QueryLogic} from "./libraries/QueryLogic.sol";
import {MerchantLogic} from "./libraries/MerchantLogic.sol";
import {SwapLogic} from "./libraries/Swap.sol";

contract ZKPayStorage {
    address internal _treasury;
    mapping(address asset => AssetManagement.PaymentAsset) internal _assets;
    mapping(bytes32 queryHash => uint248 queryNonce) internal _queryNonces;
    mapping(bytes32 queryHash => uint64 querySubmissionTimestamp) internal _querySubmissionTimestamps;
    uint248[1] internal _queryNonce;
    mapping(bytes32 queryHash => QueryLogic.QueryPayment queryPayment) internal _queryPayments;
    mapping(address merchantAddress => MerchantLogic.MerchantConfig merchantConfig) internal _merchantConfigs;

    address internal _sxt;

    // **  Swap Logic Storage ** //
    SwapLogic.SwapLogicConfig internal _swapLogicConfig;

    /// @notice mapping of source assets to swap path to USDT, set by protocol owner
    /// Path: (sourceAsset => USDT)
    mapping(address asset => bytes sourceAssetPath) internal _sourceAssetsPaths;

    /// @notice mapping from merchant address to swap path, set by merchant
    /// @dev targetAssetPath should end with the target asset; target asset is the asset that the merchant wants to receive
    /// Path: (USDT => targetAsset)
    mapping(address merchant => bytes targetAssetPath) internal _merchantTargetAssetsPaths;
}
