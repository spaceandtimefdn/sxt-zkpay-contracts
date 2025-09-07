// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ZERO_ADDRESS} from "./Constants.sol";

library MerchantLogic {
    /// @notice Emitted when a merchant updates their configuration
    /// @param merchant Address of the merchant
    /// @param payoutToken Target token address for payouts
    /// @param payoutAddresses Array of payout addresses
    /// @param payoutPercentages Array of payout percentages
    /// @param allowUserCustomPath Whether users can provide custom swap paths
    event MerchantConfigSet(
        address indexed merchant,
        address payoutToken,
        address[] payoutAddresses,
        uint32[] payoutPercentages,
        bool allowUserCustomPath
    );

    /// @notice Error thrown when payout percentages don't sum to 100%
    error InvalidPayoutPercentageSum();

    /// @notice Error thrown when payout address is zero
    error PayoutAddressCannotBeZero();

    /// @notice Error thrown when no payout recipients are provided
    error NoPayoutRecipients();

    /// @notice Error thrown when payout address and percentage arrays have different lengths
    error PayoutArrayLengthMismatch();

    /// @notice Error thrown when a payout percentage is zero
    error ZeroPayoutPercentage();

    /// @notice Error thrown when too many payout recipients are specified
    error TooManyPayoutRecipients();

    error UnsupportedPaymentMethod();

    /// @notice Error thrown when item ID callback is not configured
    error ItemIdCallbackNotConfigured();

    /// @notice Error thrown when user provides custom path but merchant doesn't allow it
    error UserCustomPathNotAllowed();

    uint32 public constant PERCENTAGE_PRECISION = 1e6;
    uint32 public constant TOTAL_PERCENTAGE = 100 * PERCENTAGE_PRECISION;
    uint256 public constant MAX_PAYOUT_RECIPIENTS = 16;

    struct MerchantConfig {
        bool allowUserCustomPath;
        address payoutToken;
        address[] payoutAddresses;
        uint32[] payoutPercentages;
    }

    struct MerchantLogicStorage {
        mapping(address merchantAddress => MerchantLogic.MerchantConfig merchantConfig) merchantConfigs;
        mapping(bytes32 => MerchantLogic.ItemIdCallbackConfig) itemIdCallbackConfigs;
    }

    bytes1 public constant SEND_METHOD = bytes1(uint8(1 << 0));
    bytes1 public constant AUTHORIZE_METHOD = bytes1(uint8(1 << 1));

    struct ItemIdCallbackConfig {
        bytes4 funcSig;
        address contractAddress;
        bool includePaymentMetadata;
        bytes1 acceptedMethods;
    }

    function setConfig(
        MerchantLogicStorage storage merchantLogicStorage,
        address merchant,
        MerchantConfig memory config
    ) internal {
        uint256 len = config.payoutAddresses.length;
        if (len == 0) {
            revert NoPayoutRecipients();
        }
        if (len > MAX_PAYOUT_RECIPIENTS) {
            revert TooManyPayoutRecipients();
        }
        if (len != config.payoutPercentages.length) {
            revert PayoutArrayLengthMismatch();
        }
        uint32 totalPercentage = 0;
        for (uint256 i = 0; i < len; ++i) {
            uint32 percentage = config.payoutPercentages[i];
            if (config.payoutAddresses[i] == ZERO_ADDRESS) {
                revert PayoutAddressCannotBeZero();
            }
            if (percentage == 0) {
                revert ZeroPayoutPercentage();
            }
            totalPercentage += percentage;
        }

        if (totalPercentage != TOTAL_PERCENTAGE) {
            revert InvalidPayoutPercentageSum();
        }

        merchantLogicStorage.merchantConfigs[merchant] = config;

        emit MerchantConfigSet(
            merchant, config.payoutToken, config.payoutAddresses, config.payoutPercentages, config.allowUserCustomPath
        );
    }

    function getConfig(MerchantLogicStorage storage merchantLogicStorage, address merchant)
        internal
        view
        returns (MerchantConfig memory config)
    {
        config = merchantLogicStorage.merchantConfigs[merchant];
    }

    function setItemIdCallback(
        MerchantLogicStorage storage merchantLogicStorage,
        address merchant,
        bytes32 itemId,
        ItemIdCallbackConfig memory callbackConfig
    ) internal {
        if (callbackConfig.acceptedMethods == 0) {
            revert UnsupportedPaymentMethod();
        }
        if (callbackConfig.acceptedMethods & ~(SEND_METHOD | AUTHORIZE_METHOD) != 0) {
            revert UnsupportedPaymentMethod();
        }
        merchantLogicStorage.itemIdCallbackConfigs[keccak256(abi.encodePacked(merchant, itemId))] = callbackConfig;
    }

    function getItemIdCallback(MerchantLogicStorage storage merchantLogicStorage, address merchant, bytes32 itemId)
        internal
        view
        returns (ItemIdCallbackConfig memory callbackConfig)
    {
        callbackConfig = merchantLogicStorage.itemIdCallbackConfigs[keccak256(abi.encodePacked(merchant, itemId))];

        if (callbackConfig.contractAddress == ZERO_ADDRESS) {
            revert ItemIdCallbackNotConfigured();
        }
    }
}
