// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IPayWall
/// @notice protocol fee is 0.5% of the source asset amount except if the source asset is SXT.
/// @notice For payment if merchant config is not set, the target asset will be sent to the merchant address directly, and default target asset will be SXT and no minimum amount of target asset is required for the item id.
interface IPayWall {
    /// @notice Emitted when the treasury address is set, treasury is used to recieve protocol fees
    /// @param treasury The new treasury address
    event TreasurySet(address indexed treasury);

    /// @notice Emitted when a payment is made
    /// @param sourceAsset The asset used for payment
    /// @param sourceAssetAmount The amount of source asset tokens used for payment
    /// @param targetAsset The target asset received
    /// @param targetAssetAmount The amount of target asset tokens received
    /// @param merchant The merchant address
    /// @param merchantPayoutAddress The merchant's payout address
    /// @param memo Additional data or information about the payment
    /// @param onBehalfOf The identifier on whose behalf the payment was made
    /// @param sender The address that initiated the payment
    event SendPayment(
        address indexed sourceAsset,
        uint248 sourceAssetAmount,
        address indexed targetAsset,
        uint248 targetAssetAmount,
        address indexed merchant,
        address indexed merchantPayoutAddress,
        bytes memo,
        bytes32 onBehalfOf,
        address indexed sender
    );

    /// @notice Sets the treasury address
    /// @param treasury The new treasury address
    function setTreasury(address treasury) external;

    /// @notice Gets the treasury address
    /// @return treasury The treasury address
    function getTreasury() external view returns (address treasury);

    /// @notice whitelist source asset for payment, source asset is the asset that will be used and swap to target asset when making payment
    /// @param sourceAssetAddress The asset to whitelist
    function whitelistSourceAsset(address sourceAssetAddress) external;

    /// @notice Removes a source asset from the payment assets
    /// @param asset The asset to remove
    function removeSourceAsset(address asset) external;

    /// @notice Checks if a source asset is whitelisted
    /// @param asset The asset to check
    /// @return isWhitelisted True if the asset is whitelisted, false otherwise
    function isSourceAssetWhitelisted(address asset) external view returns (bool isWhitelisted);

    /// @notice Sets the merchant config
    /// @dev msg.sender is the mercahnt address
    /// @param payoutAddress The payout address
    /// @param targetAsset The target asset
    /// @param itemIds array of item ids
    /// @param prices array of minimum price for each item id in target asset, decimals is dynamic based on the target asset
    function setMerchantConfig(
        address payoutAddress,
        address targetAsset,
        bytes32[] calldata itemIds,
        uint248[] calldata prices
    ) external;

    /// @notice Allows users to make payment by sending ERC20 source tokens to a target merchant
    /// @dev this function will swap source asset to target asset and send to merchant payout address,
    /// source asset will be swapped to target asset using the swap router,
    /// merchant's set config payout address will be used to recieve the target asset when user make payment,
    /// if no merchant payout address is provided, the target asset will be sent to the merchant address directly,
    /// @dev this function will revert if the source asset is not whitelisted
    /// @dev this function will revert if the item id is set and the received target asset amount is less than the minimum price for the item id
    /// @param sourceAsset The address of the source asset to send
    /// @param amount The amount of tokens of source asset to send
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param itemId The item id
    function send(
        address sourceAsset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external;

    /// @notice Allows users to make payment by sending ERC20 source tokens to a target merchant with a callback
    /// @dev this function will swap source asset to target asset and send to merchant payout address,
    /// source asset will be swapped to target asset using the swap router,
    /// merchant's set config payout address will be used to recieve the target asset when user make payment,
    /// if no merchant payout address is provided, the target asset will be sent to the merchant address directly,
    /// @dev this function will revert if the source asset is not whitelisted
    /// @dev this function will revert if the item id is set and the received target asset amount is less than the minimum price for the item id
    /// @dev ItemId is the hash of `callbackAddress` and first 4 bytes of `callbackData`
    /// @param sourceAsset The address of the source asset to send
    /// @param amount The amount of tokens of source asset to send
    /// @param onBehalfOf The identifier on whose behalf the payment is made
    /// @param merchant The merchant address
    /// @param memo Additional data or information about the payment
    /// @param callbackAddress The callback address
    /// @param callbackData The callback data
    function sendCallback(
        address sourceAsset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        address callbackAddress,
        bytes calldata callbackData
    ) external;
}
