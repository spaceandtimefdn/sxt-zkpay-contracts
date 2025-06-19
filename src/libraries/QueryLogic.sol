// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AssetManagement} from "./AssetManagement.sol";
import {ICustomLogic} from "../interfaces/ICustomLogic.sol";
import {MAX_GAS_CLIENT_CALLBACK, FEE, FEE_PRECISION} from "./Constants.sol";

/// @title QueryLogic
library QueryLogic {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when the callback client address is not the sender.
    error CallbackClientAddressShouldBeMsgSender();
    /// @notice Error thrown when the query timeout is invalid.
    error InvalidQueryTimeout();
    /// @notice Error thrown when the callback gas limit is too high.
    error CallbackGasLimitTooHigh();

    /// @notice Emitted when a new query is submitted.
    /// @param queryNonce Unique nonce for the query.
    /// @param sender The address that submitted the query.
    /// @param query The query data encoded as bytes.
    /// @param queryParameters Encoded parameters for the query.
    /// @param timeout The timeout for the query in seconds.
    /// @param callbackClientContractAddress The contract address to which results will be sent.
    /// @param callbackGasLimit The gas limit for the callback.
    /// @param callbackData Additional callback data.
    /// @param customLogicContractAddress The contract address to which results will be sent.
    /// @param queryHash The unique hash representing the query.
    event QueryReceived(
        uint248 indexed queryNonce,
        address indexed sender,
        bytes query,
        bytes queryParameters,
        uint64 timeout,
        address callbackClientContractAddress,
        uint64 callbackGasLimit,
        bytes callbackData,
        address customLogicContractAddress,
        bytes32 queryHash
    );

    /**
     * @notice Emitted when a query is canceled.
     * @param queryHash The hash of the canceled query.
     * @param caller The caller address that triggered the cancellation.
     */
    event QueryCanceled(bytes32 indexed queryHash, address indexed caller);

    /**
     * @notice Emitted when a query payment is refunded.
     * @param queryHash The hash of the refunded query.
     * @param asset The asset used for the payment.
     * @param source The source address of the payment.
     * @param amount The amount of tokens refunded.
     */
    event PaymentRefunded(bytes32 indexed queryHash, address indexed asset, address indexed source, uint248 amount);

    /**
     * @dev Struct representing a payment for a query.
     */
    struct QueryPayment {
        /// @notice The address of the token used for payment.
        address asset;
        /// @notice The amount of tokens paid.
        uint248 amount;
        /// @notice The source address of the payment.
        address source;
    }

    /**
     * @dev Struct containing details for a query.
     */
    struct QueryRequest {
        /// @notice The content of the query.
        bytes query;
        /// @notice The query related parameters.
        bytes queryParameters;
        /// @notice The timeout in block timestamp after which the query is considered expired.
        uint64 timeout;
        /// @notice The address of the contract to callback with the result.
        address callbackClientContractAddress;
        /// @notice The maximum amount of gas to use for the callback.
        /// @dev must be less or equal to MAX_GAS_CLIENT_CALLBACK
        uint64 callbackGasLimit;
        /// @notice Indicates the pre-fulfillment logic contract
        /// 0x..1; PoSQL EVM verification
        /// 0x..2; PoSQL Substrate verification
        /// 0x..3; GPT TEE signature verifier
        /// 0x..4; Spark query
        /// other; contract logic that expose `processZKpayResults`
        address customLogicContractAddress;
        /// @notice Extra data to be passed back in the callback.
        bytes callbackData;
    }

    /**
     * @notice Generates a unique hash for a query.
     * @dev This function encodes the query details into a `bytes32` hash, providing a unique identifier for each query
     * submission.
     * @param queryNonce A unique identifier for the query.
     * @param queryRequest The struct containing various query details, including the query content, type, parameters,
     * and callback information.
     * @param payment The struct containing the payment details, including the asset, amount and source.
     * @return queryHash `bytes32` hash representing the encoded query, which serves as a unique identifier for the query in
     * the system.
     */
    function generateQueryHash(uint248 queryNonce, QueryRequest calldata queryRequest, QueryPayment memory payment)
        internal
        view
        returns (bytes32 queryHash)
    {
        // binding the query hash to the contract address, query nonce, query request and payment to:
        // - ensure query hash uniqueness per query request, nonce, smart contract, chain and payment
        // - prevent reorgs from affecting the query hash and the actual payment
        queryHash = keccak256(abi.encode(block.chainid, address(this), queryNonce, queryRequest, payment));
    }

    /**
     * @dev Internal function for handling query submissions.
     * @param _queryNonce The query nonce.
     * @param _queryNonces The mapping of query hashes to query nonces.
     * @param _querySubmissionTimestamps The mapping of query hashes to query submission timestamps.
     * @param queryRequest The struct containing the query details, including query string, parameters, and callback
     * information.
     * @return queryHash unique `bytes32` query hash for the submitted query.
     */
    function submitQuery(
        uint248[1] storage _queryNonce,
        mapping(bytes32 queryHash => uint248 queryNonce) storage _queryNonces,
        mapping(bytes32 queryHash => uint64 querySubmissionTimestamp) storage _querySubmissionTimestamps,
        QueryRequest calldata queryRequest,
        QueryPayment memory payment
    ) internal returns (bytes32) {
        if (queryRequest.callbackClientContractAddress != msg.sender) {
            revert CallbackClientAddressShouldBeMsgSender();
        }

        if (queryRequest.callbackGasLimit > MAX_GAS_CLIENT_CALLBACK) {
            revert CallbackGasLimitTooHigh();
        }

        if (
            // slither-disable-next-line timestamp
            block.timestamp >= queryRequest.timeout && queryRequest.timeout > 0
        ) {
            revert InvalidQueryTimeout();
        }

        ++_queryNonce[0];

        bytes32 queryHash = generateQueryHash(_queryNonce[0], queryRequest, payment);

        _queryNonces[queryHash] = _queryNonce[0];

        _querySubmissionTimestamps[queryHash] = uint64(block.timestamp);

        emit QueryReceived(
            _queryNonce[0],
            msg.sender,
            queryRequest.query,
            queryRequest.queryParameters,
            queryRequest.timeout,
            queryRequest.callbackClientContractAddress,
            queryRequest.callbackGasLimit,
            queryRequest.callbackData,
            queryRequest.customLogicContractAddress,
            queryHash
        );

        return queryHash;
    }

    /**
     * @dev Cancel a query and refund the payment.
     * @param queryHash The unique hash for the submitted query.
     */
    function cancelQuery(
        mapping(bytes32 queryHash => QueryPayment) storage _queryPayments,
        mapping(bytes32 queryHash => uint248 queryNonce) storage _queryNonces,
        bytes32 queryHash
    ) internal {
        QueryLogic.QueryPayment memory payment = _queryPayments[queryHash];

        delete _queryNonces[queryHash];
        delete _queryPayments[queryHash];

        emit QueryCanceled(queryHash, msg.sender);

        if (payment.amount > 0) {
            emit PaymentRefunded(queryHash, payment.asset, payment.source, payment.amount);

            IERC20(payment.asset).safeTransfer(payment.source, payment.amount);
        }
    }

    /**
     * @dev Settles the query payment during fulfillment.
     * @param _assets The mapping of assets to their payment information.
     * @param customLogicContractAddress The address of the custom logic contract.
     * @param gasUsed The amount of gas used for fulfilling the query.
     * @param payment The payment details.
     * @param treasury The address of the treasury.
     * @param sxt The address of the SXT token.
     * @return paidAmount The amount paid to the merchant in source token.
     * @return refundAmount The amount refunded to the user in source token.
     * @return merchantPayoutAmount The amount paid to the merchant in source token.
     * @return protocolFeeAmount The amount of protocol fee paid in source token.
     */
    function settleQueryPayment(
        mapping(address asset => AssetManagement.PaymentAsset) storage _assets,
        address customLogicContractAddress,
        uint248 gasUsed,
        QueryPayment memory payment,
        address treasury,
        address sxt
    )
        internal
        returns (uint248 paidAmount, uint248 refundAmount, uint248 merchantPayoutAmount, uint248 protocolFeeAmount)
    {
        uint248 usedGasInWei = uint248(gasUsed * block.basefee);
        uint248 usedGasInPaymentToken = AssetManagement.convertNativeToToken(_assets, payment.asset, usedGasInWei);

        (address merchantAddress, uint248 merchantFeeInUsdValue) =
            ICustomLogic(customLogicContractAddress).getMerchantAddressAndFee();
        uint248 merchantFeeInPaymentToken =
            AssetManagement.convertUsdToToken(_assets, payment.asset, merchantFeeInUsdValue);

        paidAmount = usedGasInPaymentToken + merchantFeeInPaymentToken;
        if (paidAmount > payment.amount) {
            paidAmount = payment.amount;
        }

        protocolFeeAmount = payment.asset == sxt ? 0 : uint248((uint256(paidAmount) * FEE) / FEE_PRECISION);
        merchantPayoutAmount = paidAmount - protocolFeeAmount;

        refundAmount = payment.amount - paidAmount;

        if (merchantPayoutAmount > 0) {
            IERC20(payment.asset).safeTransfer(merchantAddress, merchantPayoutAmount);
        }
        if (refundAmount > 0) {
            IERC20(payment.asset).safeTransfer(payment.source, refundAmount);
        }
        if (protocolFeeAmount > 0) {
            IERC20(payment.asset).safeTransfer(treasury, protocolFeeAmount);
        }
    }
}
