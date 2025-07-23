// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {NATIVE_ADDRESS} from "../../src/libraries/Constants.sol";

library Setup {
    function setupAssets(mapping(address asset => AssetManagement.PaymentAsset) storage _assets, address usdcAddress)
        internal
    {
        uint8 chainlinkPricefeedDecimals = 8;

        uint8 nativeDecimals = 18;
        uint64 nativeStalePriceThresholdInSeconds = 100;
        int256 nativeTokenPrice = int256(1000 * 10 ** chainlinkPricefeedDecimals);
        address nativePriceFeed = address(new MockV3Aggregator(chainlinkPricefeedDecimals, nativeTokenPrice));

        uint8 usdcDecimals = 6;
        uint64 usdcStalePriceThresholdInSeconds = 100;
        int256 usdcTokenPrice = int256(1 * 10 ** chainlinkPricefeedDecimals);
        address usdcPriceFeed = address(new MockV3Aggregator(chainlinkPricefeedDecimals, usdcTokenPrice));

        _assets[NATIVE_ADDRESS] = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.NONE_PAYMENT_FLAG,
            priceFeed: nativePriceFeed,
            tokenDecimals: nativeDecimals,
            stalePriceThresholdInSeconds: nativeStalePriceThresholdInSeconds
        });

        _assets[usdcAddress] = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG,
            priceFeed: usdcPriceFeed,
            tokenDecimals: usdcDecimals,
            stalePriceThresholdInSeconds: usdcStalePriceThresholdInSeconds
        });
    }
}
