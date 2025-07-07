// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Utils} from "./Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NATIVE_ADDRESS, ZERO_ADDRESS, PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "./Constants.sol";
/// @title AssetManagement
/// @notice Library for managing payment assets,
/// @dev It allows for setting, removing and getting payment assets. use address(0) as an asset address to refer to native token.

library AssetManagement {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when trying to remove the native token
    error NativeTokenCannotBeRemoved();
    /// @notice Error thrown when the price feed is invalid
    error InvalidPriceFeed();
    /// @notice Error thrown when the asset is not found
    error AssetNotFound();
    /// @notice Error thrown when the price feed data is invalid
    error InvalidPriceFeedData();
    /// @notice Error thrown when the price feed data is stale
    error StalePriceFeedData();
    /// @notice Error thrown when the asset is not supported for this method
    error AssetIsNotSupportedForThisMethod();
    /// @notice Error thrown when the target address is zero
    error TargetAddressCannotBeZero();

    /// @notice Emitted when a new asset is added
    /// @param asset The asset address
    /// @param allowedPaymentTypes The allowed payment types presented as a bytes1 bitmask
    /// @param priceFeed The price feed address
    /// @param tokenDecimals The token decimals
    /// @param stalePriceThresholdInSeconds The stale price threshold in seconds
    event AssetAdded(
        address indexed asset,
        bytes1 allowedPaymentTypes,
        address priceFeed,
        uint8 tokenDecimals,
        uint64 stalePriceThresholdInSeconds
    );

    /// @notice Emitted when an asset is removed
    /// @param asset The asset address
    event AssetRemoved(address asset);

    /**
     * @notice Defines methods for accepted asset types within the ZKpay protocol.
     * @dev Indicates whether an asset can be used for direct payment to target protocol or for on-demand queries.
     */
    struct PaymentAsset {
        /// @notice 1 byte representing allowed payment types, 0x01 = Send, 0x02 = Query
        bytes1 allowedPaymentTypes;
        /// @notice  Price oracle
        address priceFeed;
        /// @notice  token decimals, added here in case erc20 token isn't fully compliant and doesn't expose that method.
        uint8 tokenDecimals;
        /// @notice threshold for price feed data in seconds
        uint64 stalePriceThresholdInSeconds;
    }

    bytes1 public constant NONE_PAYMENT_FLAG = bytes1(uint8(0x00));
    bytes1 public constant SEND_PAYMENT_FLAG = bytes1(uint8(0x01) << uint8(PaymentType.Send));
    bytes1 public constant QUERY_PAYMENT_FLAG = bytes1(uint8(0x01) << uint8(PaymentType.Query));

    /**
     * @notice Specifies the type of payment being made.
     * @dev Used to distinguish between credit purchases and on-demand query payments.
     */
    enum PaymentType {
        /// @notice for sending payments, ie. calling `pay` function
        Send,
        /// @notice for querying payments, ie. calling `query*` functions
        Query
    }

    /// @notice Validates the price feed
    /// @param paymentAsset payment asset
    function _validatePriceFeed(PaymentAsset memory paymentAsset) internal view {
        if (paymentAsset.priceFeed == ZERO_ADDRESS || !Utils.isContract(paymentAsset.priceFeed)) {
            revert InvalidPriceFeed();
        }

        // slither-disable-next-line unused-return
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(paymentAsset.priceFeed).latestRoundData();

        // Check for invalid or incomplete price data
        if (answer <= 0 || startedAt == 0 || answeredInRound < roundId) {
            revert InvalidPriceFeedData();
        }

        // slither-disable-next-line timestamp
        if (updatedAt + paymentAsset.stalePriceThresholdInSeconds < block.timestamp) {
            revert StalePriceFeedData();
        }
    }

    /// @notice Sets the payment asset
    /// @param _assets assets mapping
    /// @param asset token address
    /// @param paymentAsset payment asset to set
    function set(
        mapping(address asset => PaymentAsset) storage _assets,
        address asset,
        PaymentAsset memory paymentAsset
    ) internal {
        _validatePriceFeed(paymentAsset);

        _assets[asset] = paymentAsset;
        emit AssetAdded(
            asset,
            paymentAsset.allowedPaymentTypes,
            paymentAsset.priceFeed,
            paymentAsset.tokenDecimals,
            paymentAsset.stalePriceThresholdInSeconds
        );
    }

    /// @notice Removes an asset from the assets mapping
    /// @param _assets assets mapping
    /// @param asset token address
    /// @dev native token cannot be removed as it's used for gas cost when fulfilling queries
    function remove(mapping(address asset => PaymentAsset) storage _assets, address asset) internal {
        if (asset == NATIVE_ADDRESS) revert NativeTokenCannotBeRemoved();

        delete _assets[asset];
        emit AssetRemoved(asset);
    }

    /// @notice Gets the payment asset
    /// @param _assets assets mapping
    /// @param assetAddress token address
    /// @return asset
    function get(mapping(address asset => PaymentAsset) storage _assets, address assetAddress)
        internal
        view
        returns (PaymentAsset storage asset)
    {
        asset = _assets[assetAddress];
        if (asset.priceFeed == ZERO_ADDRESS) revert AssetNotFound();
    }

    /// @notice Checks if an asset is supported for a given payment type
    /// @param _assets assets mapping
    /// @param assetAddress token address
    /// @param paymentType payment type
    /// @return true if the asset is supported for the payment type, false otherwise
    function isSupported(
        mapping(address asset => PaymentAsset) storage _assets,
        address assetAddress,
        PaymentType paymentType
    ) internal view returns (bool) {
        if (assetAddress == NATIVE_ADDRESS) {
            return false;
        }
        return (_assets[assetAddress].allowedPaymentTypes >> uint8(paymentType)) & bytes1(0x01) == bytes1(0x01);
    }

    /// @notice Gets the price of an asset
    /// @param _assets assets mapping
    /// @param assetAddress token address
    /// @return safePrice price of the asset
    /// @return priceFeedDecimals price feed decimals
    function _getPrice(mapping(address asset => PaymentAsset) storage _assets, address assetAddress)
        internal
        view
        returns (uint256 safePrice, uint8 priceFeedDecimals)
    {
        PaymentAsset storage paymentAsset = _assets[assetAddress];
        AggregatorV3Interface priceFeedContract = AggregatorV3Interface(paymentAsset.priceFeed);

        // slither-disable-next-line unused-return
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeedContract.latestRoundData();

        // Check for invalid or incomplete price data
        if (price <= 0 || startedAt == 0 || answeredInRound < roundId) {
            revert InvalidPriceFeedData();
        }

        // slither-disable-next-line timestamp
        if (block.timestamp > updatedAt + paymentAsset.stalePriceThresholdInSeconds) {
            revert StalePriceFeedData();
        }

        safePrice = uint256(price);
        priceFeedDecimals = priceFeedContract.decimals();
    }

    /**
     * @dev Internal helper function to convert a token amount to its equivalent USD value.
     * @param _assets assets mapping
     * @param tokenAmount The amount of the token (in its smallest unit, e.g., wei for ETH).
     * @param assetAddress The address of the asset to convert.
     * @return usdValue The equivalent USD value in 18 decimal places.
     * @dev This function could revert if `tokenAmount * safePrice` overflows uint248
     */
    function convertToUsd(
        mapping(address asset => PaymentAsset) storage _assets,
        address assetAddress,
        uint248 tokenAmount
    ) internal view returns (uint248 usdValue) {
        PaymentAsset storage paymentAsset = _assets[assetAddress];
        (uint256 safePrice, uint8 priceFeedDecimals) = _getPrice(_assets, assetAddress);

        if (paymentAsset.tokenDecimals + priceFeedDecimals > 18) {
            usdValue = uint248((tokenAmount * safePrice) / 10 ** (paymentAsset.tokenDecimals + priceFeedDecimals - 18));
        } else {
            usdValue = uint248((tokenAmount * safePrice) * 10 ** (18 - paymentAsset.tokenDecimals - priceFeedDecimals));
        }
    }

    /**
     * @notice Handles a query payment for a given asset.
     * @param _assets The mapping of assets to their payment information.
     * @param assetAddress The address of the asset to handle the payment for.
     * @param tokenAmount The amount of the asset to handle the payment for.
     * @return actualAmountReceived The actual amount received by the contract.
     * @return amountInUSD The amount in USD.
     * @dev This function could revert if `tokenAmount * safePrice` overflows uint248
     */
    function handleQueryPayment(
        mapping(address asset => PaymentAsset) storage _assets,
        address assetAddress,
        uint248 tokenAmount
    ) internal returns (uint248 actualAmountReceived, uint248 amountInUSD) {
        if (!isSupported(_assets, assetAddress, PaymentType.Query)) {
            revert AssetIsNotSupportedForThisMethod();
        }

        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(this));
        IERC20(assetAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(this));

        actualAmountReceived = uint248(balanceAfter - balanceBefore);

        amountInUSD = convertToUsd(_assets, assetAddress, actualAmountReceived);
    }

    /**
     * @dev Internal helper function to convert a USD value to its equivalent token amount.
     * @param usdValue The USD value to convert in 18 decimals.
     * @param asset The address of the asset to convert.
     * @return tokenAmount The equivalent token amount.
     */
    function convertUsdToToken(mapping(address asset => PaymentAsset) storage _assets, address asset, uint248 usdValue)
        internal
        view
        returns (uint248 tokenAmount)
    {
        (uint256 safePrice, uint8 priceFeedDecimals) = _getPrice(_assets, asset);

        uint248 adjustedPrice = uint248(safePrice) * uint248(10 ** (18 - priceFeedDecimals)); // price in 18 decimals
        tokenAmount = (usdValue * uint248(10 ** _assets[asset].tokenDecimals)) / adjustedPrice;
    }

    /**
     * @dev Internal helper function to convert a native amount to its equivalent token amount.
     * @param _assets assets mapping
     * @param asset The address of the asset to convert.
     * @param nativeAmount The amount of the native token.
     * @return tokenAmount The equivalent token amount.
     */
    function convertNativeToToken(
        mapping(address asset => PaymentAsset) storage _assets,
        address asset,
        uint248 nativeAmount
    ) internal view returns (uint248 tokenAmount) {
        if (asset == NATIVE_ADDRESS) {
            return nativeAmount;
        }
        uint248 usdValue = convertToUsd(_assets, NATIVE_ADDRESS, nativeAmount);
        tokenAmount = convertUsdToToken(_assets, asset, usdValue);
    }

    /// @notice Sends a payment to a target address.
    /// @param _assets The mapping of assets to their payment information.
    /// @param asset The address of the asset to send the payment for.
    /// @param amount The amount of the asset to send.
    /// @param target The address of the target to send the payment to.
    /// @param treasury The address of the treasury to send the protocol fee to.
    /// @param sxt The address of the SXT token.
    function send(
        mapping(address asset => PaymentAsset) storage _assets,
        address asset,
        uint248 amount,
        address target,
        address treasury,
        address sxt
    ) internal returns (uint248 actualAmountReceived, uint248 amountInUSD, uint248 protocolFeeAmount) {
        if (target == ZERO_ADDRESS) {
            revert TargetAddressCannotBeZero();
        }

        if (!isSupported(_assets, asset, PaymentType.Send)) {
            revert AssetIsNotSupportedForThisMethod();
        }

        protocolFeeAmount = asset == sxt ? 0 : uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        uint248 transferAmount = amount - protocolFeeAmount;

        uint256 balanceBefore = IERC20(asset).balanceOf(target);
        if (protocolFeeAmount > 0) {
            SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, treasury, protocolFeeAmount);
        }
        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, target, transferAmount);
        uint256 balanceAfter = IERC20(asset).balanceOf(target);

        actualAmountReceived = uint248(balanceAfter - balanceBefore);

        amountInUSD = convertToUsd(_assets, asset, actualAmountReceived);
    }
}
