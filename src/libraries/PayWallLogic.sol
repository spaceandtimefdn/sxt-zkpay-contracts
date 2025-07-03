// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PayWallLogic
/// @notice Library for managing merchant paywall prices
library PayWallLogic {
    struct PayWallLogicStorage {
        mapping(address merchant => mapping(bytes32 item => uint248 price)) paywallPrices;
    }

    /// @notice Emitted when the price for an item is set
    event ItemPriceSet(address indexed merchant, bytes32 indexed item, uint248 price);

    /// @notice set the price for an item
    /// @param _paywallLogicStorage the storage of the paywall logic
    /// @param merchant the merchant address
    /// @param item the item hash
    /// @param price the price
    function setItemPrice(
        PayWallLogicStorage storage _paywallLogicStorage,
        address merchant,
        bytes32 item,
        uint248 price
    ) internal {
        _paywallLogicStorage.paywallPrices[merchant][item] = price;
        emit ItemPriceSet(merchant, item, price);
    }

    /// @notice get the price for an item
    /// @param _paywallLogicStorage the storage of the paywall logic
    /// @param merchant the merchant address
    /// @param item the item hash
    /// @return the price
    function getItemPrice(PayWallLogicStorage storage _paywallLogicStorage, address merchant, bytes32 item)
        internal
        view
        returns (uint248)
    {
        return _paywallLogicStorage.paywallPrices[merchant][item];
    }
}
