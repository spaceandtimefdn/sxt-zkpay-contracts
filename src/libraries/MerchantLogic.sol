// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ZERO_ADDRESS} from "./Constants.sol";

library MerchantLogic {
    /// @notice Emitted when a merchant updates their configuration
    /// @param merchant Address of the merchant
    /// @param payoutToken Target token address for payouts
    /// @param payoutAddress Address that will receive payouts
    /// @param fulfillerPercentage Percentage of payout that goes to fulfiller in 6 decimals precision
    event MerchantConfigSet(
        address indexed merchant, address payoutToken, address payoutAddress, uint32 fulfillerPercentage
    );

    /// @notice Error thrown when fulfillerPercentage is greater than 100% (1e6 precision)
    error InvalidFulfillerPercentage();

    /// @notice Error thrown when payoutAddress is zero
    error PayoutAddressCannotBeZero();

    uint32 public constant PERCENTAGE_PRECISION = 1e6;
    uint32 public constant MAX_PERCENTAGE = 100 * PERCENTAGE_PRECISION;

    struct MerchantConfig {
        address payoutToken;
        address payoutAddress;
        uint32 fulfillerPercentage;
    }

    struct MerchantLogicStorage {
        mapping(address merchantAddress => MerchantLogic.MerchantConfig merchantConfig) merchantConfigs;
        mapping(bytes32 => MerchantLogic.ItemIdCallbackConfig) itemIdCallbackConfigs;
    }

    struct ItemIdCallbackConfig {
        bytes4 funcSig;
        address contractAddress;
        bool includePaymentMetadata;
    }

    function setConfig(
        MerchantLogicStorage storage merchantLogicStorage,
        address merchant,
        MerchantConfig memory config
    ) internal {
        if (config.fulfillerPercentage > MAX_PERCENTAGE) {
            revert InvalidFulfillerPercentage();
        }
        if (config.payoutAddress == ZERO_ADDRESS) {
            revert PayoutAddressCannotBeZero();
        }

        merchantLogicStorage.merchantConfigs[merchant] = config;

        emit MerchantConfigSet(merchant, config.payoutToken, config.payoutAddress, config.fulfillerPercentage);
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
        merchantLogicStorage.itemIdCallbackConfigs[keccak256(abi.encodePacked(merchant, itemId))] = callbackConfig;
    }

    function getItemIdCallback(MerchantLogicStorage storage merchantLogicStorage, address merchant, bytes32 itemId)
        internal
        view
        returns (ItemIdCallbackConfig memory callbackConfig)
    {
        callbackConfig = merchantLogicStorage.itemIdCallbackConfigs[keccak256(abi.encodePacked(merchant, itemId))];
    }
}
