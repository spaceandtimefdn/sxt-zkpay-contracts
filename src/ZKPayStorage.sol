// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "./libraries/AssetManagement.sol";
import {QueryLogic} from "./libraries/QueryLogic.sol";

contract ZKPayStorage {
    address internal _treasury;
    mapping(address asset => AssetManagement.PaymentAsset) internal _assets;
    mapping(bytes32 queryHash => uint248 queryNonce) internal _queryNonces;
    mapping(bytes32 queryHash => uint64 querySubmissionTimestamp) internal _querySubmissionTimestamps;
    uint248[1] internal _queryNonce;
    mapping(bytes32 queryHash => QueryLogic.QueryPayment queryPayment) internal _queryPayments;
}
