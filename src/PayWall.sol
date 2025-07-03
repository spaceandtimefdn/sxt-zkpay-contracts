// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./PayWallStorage.sol";
import {SwapLogicLib} from "./libraries/SwapLogicLib.sol";
import "./interfaces/IPayWall.sol";

/// @title PayWall – ERC‑20 payment router with Uniswap settlement & fee capture.
contract PayWall is IPayWall, PayWallStorage {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address _router, address _sxt, address _initialTreasury) PayWallStorage(_router, _sxt) {
        require(_initialTreasury != address(0), "TREASURY_ZERO");
        treasury = _initialTreasury;
        emit TreasurySet(_initialTreasury);
    }

    /*//////////////////////////////////////////////////////////////////////////
                              INTERNAL Methods
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the payable address for a merchant (config + fallback).
    function _payoutAddress(address merchant) internal view returns (address) {
        address cfg = merchantConfig[merchant].payoutAddress;
        return cfg == address(0) ? merchant : cfg;
    }

    /// @dev Returns target asset for a merchant (config + default SXT).
    function _targetAsset(address merchant) internal view returns (address) {
        address cfg = merchantConfig[merchant].targetAsset;
        return cfg == address(0) ? SXT : cfg;
    }

    /// @dev Fetch minimum price configured for `(merchant,itemId)`.
    function _minPrice(address merchant, bytes32 itemId) internal view returns (uint248) {
        return merchantConfig[merchant].minPrice[itemId];
    }

    function _setMinPrices(address merchant, bytes32[] calldata itemIds, uint248[] calldata prices) internal {
        uint256 len = itemIds.length;
        require(len == prices.length, "MISMATCHED_ARRAYS");
        for (uint256 i; i < len; ++i) {
            merchantConfig[merchant].minPrice[itemIds[i]] = prices[i];
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                              ADMIN (OWNER) FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayWall
    function setTreasury(address _treasury) external override onlyOwner {
        require(_treasury != address(0), "TREASURY_ZERO");
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @inheritdoc IPayWall
    function getTreasury() external view override returns (address) {
        return treasury;
    }

    /// @inheritdoc IPayWall
    function whitelistSourceAsset(address asset) external override onlyOwner {
        require(!whitelistedSource[asset], "ALREADY_WHITELISTED");
        whitelistedSource[asset] = true;
    }

    /// @inheritdoc IPayWall
    function removeSourceAsset(address asset) external override onlyOwner {
        require(whitelistedSource[asset], "NOT_WHITELISTED");
        whitelistedSource[asset] = false;
    }

    /// @inheritdoc IPayWall
    function isSourceAssetWhitelisted(address asset) external view override returns (bool) {
        return whitelistedSource[asset];
    }

    /*//////////////////////////////////////////////////////////////////////////
                              MERCHANT CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayWall
    function setMerchantConfig(
        address payoutAddress,
        address targetAsset,
        bytes32[] calldata itemIds,
        uint248[] calldata prices
    ) external override {
        MerchantConfig storage cfg = merchantConfig[msg.sender];
        cfg.payoutAddress = payoutAddress;
        cfg.targetAsset = targetAsset;
        _setMinPrices(msg.sender, itemIds, prices);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               USER‑FACING PAYMENT FLOW
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayWall
    function send(
        address sourceAsset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external override nonReentrant {
        _corePayment(sourceAsset, amount, onBehalfOf, merchant, memo, itemId);
    }

    /// @inheritdoc IPayWall
    function sendCallback(
        address sourceAsset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        address callbackAddress,
        bytes calldata callbackData
    ) external override nonReentrant {
        // Item‑ID = keccak256( callbackAddress || first‑4‑bytes(selector) )
        bytes4 selector;
        assembly {
            selector := shr(224, calldataload(callbackData.offset))
        }
        bytes32 itemId = keccak256(abi.encodePacked(callbackAddress, selector));

        uint256 received = _corePayment(sourceAsset, amount, onBehalfOf, merchant, memo, itemId);

        // fire-and-forget to callback (no revert propagation, gas‑stipend = 100k)
        // If merchants need guaranteed delivery they can do pull‑based designs.
        (bool ok,) = callbackAddress.call{gas: 100_000}(callbackData);
        require(ok, "CALLBACK_FAILED");

        // silence stack‑depth warnings
        received;
    }

    /*//////////////////////////////////////////////////////////////////////////
                         INTERNAL SHARED PAYMENT IMPLEMENTATION
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Core payment logic used by both send() and sendCallback().
     * @return targetAmount paid to merchant (for potential downstream use).
     */
    function _corePayment(
        address sourceAsset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) internal returns (uint256 targetAmount) {
        require(merchant != address(0), "MERCHANT_ZERO");
        require(whitelistedSource[sourceAsset], "SRC_NOT_WHITELISTED");
        require(amount > 0, "AMOUNT_ZERO");

        // Pull funds
        IERC20(sourceAsset).safeTransferFrom(msg.sender, address(this), amount);

        // --- Protocol fee (0.5 % unless source asset is SXT) -----------------
        uint256 fee = sourceAsset == SXT ? 0 : (amount * 5) / 1000;
        if (fee > 0) {
            IERC20(sourceAsset).safeTransfer(treasury, fee);
        }

        uint256 amountAfterFee = amount - fee;

        // --- Merchant payout logic ------------------------------------------
        address payout = _payoutAddress(merchant);
        address tgtAsset = _targetAsset(merchant);

        if (sourceAsset == tgtAsset) {
            // No swap needed
            targetAmount = amountAfterFee;
            IERC20(tgtAsset).safeTransfer(payout, targetAmount);
        } else {
            // Swap then forward
            targetAmount = SwapLogicLib.swapExactInput(
                swapRouter,
                sourceAsset,
                tgtAsset,
                amountAfterFee,
                address(this) // receive here → size‑check → forward
            );
            IERC20(tgtAsset).safeTransfer(payout, targetAmount);
        }

        // --- Business‑logic price floor enforcement --------------------------
        uint248 minPrice = _minPrice(merchant, itemId);
        if (minPrice > 0) {
            require(targetAmount >= minPrice, "BELOW_MIN_PRICE");
        }

        // --- Emit canonical log ---------------------------------------------
        emit SendPayment(
            sourceAsset,
            uint248(amount),
            tgtAsset,
            uint248(targetAmount),
            merchant,
            payout,
            memo,
            onBehalfOf,
            msg.sender
        );
    }
}
