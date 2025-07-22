// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {ZKPayStorage} from "./ZKPayStorage.sol";
import {IZKPay} from "./interfaces/IZKPay.sol";
import {AssetManagement} from "./libraries/AssetManagement.sol";
import {QueryLogic} from "./libraries/QueryLogic.sol";
import {MerchantLogic} from "./libraries/MerchantLogic.sol";
import {IZKPayClient} from "./interfaces/IZKPayClient.sol";
import {ICustomLogic} from "./interfaces/ICustomLogic.sol";
import {NATIVE_ADDRESS, ZERO_ADDRESS} from "./libraries/Constants.sol";
import {SwapLogic} from "./libraries/SwapLogic.sol";
import {PayWallLogic} from "./libraries/PayWallLogic.sol";
import {EscrowPayment} from "./libraries/EscrowPayment.sol";

// slither-disable-next-line locked-ether
contract ZKPay is ZKPayStorage, IZKPay, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using MerchantLogic for mapping(address merchant => MerchantLogic.MerchantConfig);
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using EscrowPayment for EscrowPayment.EscrowPaymentStorage;

    error TreasuryAddressCannotBeZero();
    error TreasuryAddressSameAsCurrent();
    error ValueExceedsUint248Limit();
    error InvalidQueryHash();
    error QueryTimeout();
    error OnlyQuerySourceCanCancel();
    error QueryHasNotExpired();
    error NotEnoughGasToExecuteCallback();
    error NotErc20Token();
    error SXTAddressCannotBeZero();
    error InsufficientPayment();
    error InvalidCallbackData();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        address treasury,
        address sxt,
        address nativeTokenPriceFeed,
        uint8 nativeTokenDecimals,
        uint64 nativeTokenStalePriceThresholdInSeconds,
        SwapLogic.SwapLogicConfig calldata swapLogicConfig
    ) external initializer {
        __Ownable_init(owner);
        __ReentrancyGuard_init();
        _setTreasury(treasury);
        _setSXT(sxt);
        _swapLogicStorage.setConfig(swapLogicConfig);

        AssetManagement.set(
            _assets,
            NATIVE_ADDRESS,
            AssetManagement.PaymentAsset({
                allowedPaymentTypes: AssetManagement.NONE_PAYMENT_FLAG,
                priceFeed: nativeTokenPriceFeed,
                tokenDecimals: nativeTokenDecimals,
                stalePriceThresholdInSeconds: nativeTokenStalePriceThresholdInSeconds
            })
        );
    }

    function _setSXT(address sxt) internal {
        if (sxt == ZERO_ADDRESS) {
            revert SXTAddressCannotBeZero();
        }
        _sxt = sxt;
    }

    function _setTreasury(address treasury) internal {
        if (treasury == ZERO_ADDRESS) {
            revert TreasuryAddressCannotBeZero();
        }

        if (treasury == _treasury) {
            revert TreasuryAddressSameAsCurrent();
        }

        _treasury = treasury;
        emit TreasurySet(treasury);
    }

    /// @inheritdoc IZKPay
    function setTreasury(address treasury) external onlyOwner {
        _setTreasury(treasury);
    }

    /// @inheritdoc IZKPay
    function getTreasury() external view returns (address treasury) {
        return _treasury;
    }

    /// @inheritdoc IZKPay
    function getSXT() external view returns (address sxt) {
        return _sxt;
    }

    /// @inheritdoc IZKPay
    function setPaymentAsset(
        address assetAddress,
        AssetManagement.PaymentAsset calldata paymentAsset,
        bytes calldata path
    ) external onlyOwner {
        address originAsset = SwapLogic.calldataExtractPathOriginAsset(path);
        if (originAsset != assetAddress) {
            revert SwapLogic.InvalidPath();
        }

        AssetManagement.set(_assets, assetAddress, paymentAsset);
        _swapLogicStorage.setSourceAssetPath(path);
    }

    /// @inheritdoc IZKPay
    function removePaymentAsset(address asset) external onlyOwner {
        AssetManagement.remove(_assets, asset);
    }

    /// @inheritdoc IZKPay
    function getPaymentAsset(address asset) external view returns (AssetManagement.PaymentAsset memory paymentAsset) {
        return AssetManagement.get(_assets, asset);
    }

    function _query(address asset, uint248 amount, QueryLogic.QueryRequest calldata queryRequest)
        internal
        returns (bytes32 queryHash)
    {
        (uint248 actualAmountReceived, uint248 amountInUSD) = AssetManagement.handleQueryPayment(_assets, asset, amount);

        bytes32 itemId = bytes32(uint256(uint160(queryRequest.customLogicContractAddress)));

        // slither-disable-next-line unused-return
        (address merchant,) = ICustomLogic(queryRequest.customLogicContractAddress).getMerchantAddressAndFee();

        uint248 itemPrice = _paywallLogicStorage.getItemPrice(merchant, itemId);
        if (amountInUSD < itemPrice) {
            revert InsufficientPayment();
        }

        QueryLogic.QueryPayment memory queryPayment =
            QueryLogic.QueryPayment({asset: asset, amount: actualAmountReceived, source: msg.sender});

        queryHash =
            QueryLogic.submitQuery(_queryNonce, _queryNonces, _querySubmissionTimestamps, queryRequest, queryPayment);

        _queryPayments[queryHash] = queryPayment;

        emit NewQueryPayment(queryHash, asset, actualAmountReceived, msg.sender, amountInUSD);
    }

    /**
     * @dev Validates the query request.
     * @param queryHash The unique hash for the submitted query.
     * @param queryRequest The query request.
     */
    function _validateQueryRequest(bytes32 queryHash, QueryLogic.QueryRequest calldata queryRequest) internal view {
        uint248 queryNonce = _queryNonces[queryHash];
        if (queryNonce == 0) revert InvalidQueryHash();

        bytes32 calulatedQueryHash = QueryLogic.generateQueryHash(queryNonce, queryRequest, _queryPayments[queryHash]);

        if (calulatedQueryHash != queryHash) {
            revert InvalidQueryHash();
        }
    }

    /// @inheritdoc IZKPay
    function validateQueryRequest(bytes32 queryHash, QueryLogic.QueryRequest calldata queryRequest) external view {
        _validateQueryRequest(queryHash, queryRequest);
    }

    /// @inheritdoc IZKPay
    function query(address asset, uint248 amount, QueryLogic.QueryRequest calldata queryRequest)
        external
        nonReentrant
        returns (bytes32 queryHash)
    {
        return _query(asset, amount, queryRequest);
    }

    /// @inheritdoc IZKPay
    function cancelExpiredQuery(bytes32 queryHash, QueryLogic.QueryRequest calldata queryRequest)
        external
        nonReentrant
    {
        _validateQueryRequest(queryHash, queryRequest);

        // slither-disable-next-line timestamp
        if (block.timestamp < queryRequest.timeout || queryRequest.timeout == 0) {
            revert QueryHasNotExpired();
        }

        QueryLogic.cancelQuery(_queryPayments, _queryNonces, queryHash);
    }

    /// @inheritdoc IZKPay
    function fulfillQuery(bytes32 queryHash, QueryLogic.QueryRequest calldata queryRequest, bytes calldata queryResult)
        external
        nonReentrant
        returns (uint248 gasUsed)
    {
        _validateQueryRequest(queryHash, queryRequest);

        QueryLogic.QueryPayment memory payment = _queryPayments[queryHash];

        delete _queryNonces[queryHash];
        delete _queryPayments[queryHash];

        // slither-disable-next-line timestamp
        if (block.timestamp >= queryRequest.timeout && queryRequest.timeout != 0) {
            revert QueryTimeout();
        }

        bytes memory results = ICustomLogic(queryRequest.customLogicContractAddress).execute(queryRequest, queryResult);

        bool success = false;
        uint256 initialGas = gasleft();
        try IZKPayClient(queryRequest.callbackClientContractAddress).zkPayCallback{gas: queryRequest.callbackGasLimit}(
            queryHash, results, queryRequest.callbackData
        ) {
            success = true;
        } catch {
            success = false;
        }
        gasUsed = uint248(initialGas - gasleft());
        if (success) {
            emit CallbackSucceeded(queryHash, queryRequest.callbackClientContractAddress);
        } else {
            emit CallbackFailed(queryHash, queryRequest.callbackClientContractAddress);
        }

        (uint248 paidAmount, uint248 refundAmount, uint248 merchantPayoutAmount, uint248 protocolFeeAmount) = QueryLogic
            .settleQueryPayment(_assets, queryRequest.customLogicContractAddress, gasUsed, payment, _treasury, _sxt);

        emit PaymentSettled(queryHash, paidAmount, refundAmount, merchantPayoutAmount, protocolFeeAmount);
        emit QueryFulfilled(queryHash);
    }

    /// @inheritdoc IZKPay
    function send(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external nonReentrant {
        if (asset == NATIVE_ADDRESS) {
            revert NotErc20Token();
        }

        (uint248 actualAmountReceived, uint248 amountInUSD, uint248 protocolFeeAmount) =
            _assets.send(asset, amount, merchant, _treasury, _sxt);

        uint248 itemPrice = _paywallLogicStorage.getItemPrice(merchant, itemId);
        if (amountInUSD < itemPrice) {
            revert InsufficientPayment();
        }

        emit SendPayment(
            asset, actualAmountReceived, protocolFeeAmount, onBehalfOf, merchant, memo, amountInUSD, msg.sender, itemId
        );
    }

    /// @inheritdoc IZKPay
    function authorize(EscrowPayment.Transaction calldata transaction, bytes32 itemId)
        external
        nonReentrant
        returns (bytes32 transactionHash)
    {
        transactionHash = EscrowPayment.authorize(_escrowPaymentStorage, transaction, itemId);
    }

    /// @inheritdoc IZKPay
    function setMerchantConfig(MerchantLogic.MerchantConfig calldata config, bytes calldata path) external {
        _merchantConfigs.set(msg.sender, config);
        _swapLogicStorage.setMerchantTargetAssetPath(msg.sender, path);
    }

    /// @inheritdoc IZKPay
    function getMerchantConfig(address merchant) external view returns (MerchantLogic.MerchantConfig memory config) {
        return _merchantConfigs.get(merchant);
    }

    /// @inheritdoc IZKPay
    function setPaywallItemPrice(bytes32 item, uint248 price) external {
        _paywallLogicStorage.setItemPrice(msg.sender, item, price);
    }

    /// @inheritdoc IZKPay
    function getPaywallItemPrice(bytes32 item, address merchant) external view returns (uint248 price) {
        return _paywallLogicStorage.getItemPrice(merchant, item);
    }
}
