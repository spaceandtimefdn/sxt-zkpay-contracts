// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library MerchantLogic {
    /// @notice Emitted when a merchant updates their configuration
    /// @param merchant Address of the merchant
    /// @param payoutToken Target token address for payouts
    /// @param payoutAddress Address that will receive payouts
    /// @param fulfillerPercentage Percentage of payout that goes to query fulfiller in 6 decimals precision
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

    function set(
        mapping(address merchant => MerchantConfig) storage merchantConfigs,
        address merchant,
        MerchantConfig memory config
    ) internal {
        if (config.fulfillerPercentage > MAX_PERCENTAGE) {
            revert InvalidFulfillerPercentage();
        }
        if (config.payoutAddress == address(0)) {
            revert PayoutAddressCannotBeZero();
        }

        merchantConfigs[merchant] = config;

        emit MerchantConfigSet(merchant, config.payoutToken, config.payoutAddress, config.fulfillerPercentage);
    }

    function get(mapping(address merchant => MerchantConfig) storage merchantConfigs, address merchant)
        internal
        view
        returns (MerchantConfig memory config)
    {
        config = merchantConfigs[merchant];
    }
}
