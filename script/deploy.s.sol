// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/* solhint-disable no-console */
/* solhint-disable gas-small-strings */

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {SwapLogic} from "../src/libraries/SwapLogic.sol";

/// @title Deploy
/// @notice Deploy the ZKPay contract
/// @dev This script is used to deploy the ZKPay contract
/// @dev It also sets the USDC payment asset
contract Deploy is Script {
    using stdJson for string;

    /* solhint-disable gas-struct-packing */
    struct Config {
        // First slot: small integers packed together
        uint8 usdcTokenDecimals;
        uint64 usdcTokenStalePriceThresholdInSeconds;
        // Remaining slots: addresses (each takes a full slot)
        address zkpayAdmin;
        address usdcTokenAddress;
        address usdcTokenPriceFeed;
        address router;
        address usdt;
        bytes usdcToUsdtPath;
    }
    /* solhint-enable gas-struct-packing */

    function run() external {
        // Read configuration from JSON file
        Config memory config = _readConfig();

        // Deploy contracts
        vm.startBroadcast();

        // Deploy ZKPay
        ZKPay zkpay =
            new ZKPay(config.zkpayAdmin, SwapLogic.SwapLogicConfig({router: config.router, usdt: config.usdt}));

        console.log("ZKPay deployed at:", address(zkpay));

        // Set USDC payment asset
        AssetManagement.PaymentAsset memory usdcPaymentAsset = AssetManagement.PaymentAsset({
            priceFeed: config.usdcTokenPriceFeed,
            tokenDecimals: config.usdcTokenDecimals,
            stalePriceThresholdInSeconds: config.usdcTokenStalePriceThresholdInSeconds
        });
        zkpay.setPaymentAsset(config.usdcTokenAddress, usdcPaymentAsset, config.usdcToUsdtPath);

        vm.stopBroadcast();

        // Create output JSON with deployed contract addresses
        string memory outputJson = _createFormattedOutputJson(address(zkpay), config);

        // Write output to file
        string memory outputPath = string.concat(vm.projectRoot(), "/script/output/output.json");
        vm.writeFile(outputPath, outputJson);
        console.log("Deployment information written to:", outputPath);
    }

    /// @notice Read configuration from JSON file
    /// @return config The configuration struct populated with values from the JSON file
    function _readConfig() internal view returns (Config memory config) {
        string memory configPath = string.concat(vm.projectRoot(), "/script/config.json");
        string memory configJson = vm.readFile(configPath);

        // zkpay section
        config.zkpayAdmin = configJson.readAddress(".zkpayAdmin");

        // usdc payment asset section
        config.usdcTokenAddress = configJson.readAddress(".usdcTokenAddress");
        config.usdcTokenPriceFeed = configJson.readAddress(".usdcTokenPriceFeed");
        config.usdcTokenDecimals = uint8(configJson.readUint(".usdcTokenDecimals"));
        config.usdcTokenStalePriceThresholdInSeconds =
            uint64(configJson.readUint(".usdcTokenStalePriceThresholdInSeconds"));

        // swap logic section
        config.router = configJson.readAddress(".router");
        config.usdt = configJson.readAddress(".usdt");
        config.usdcToUsdtPath = configJson.readBytes(".usdcToUsdtPath");
    }

    /// @notice Create a formatted JSON output with deployed contract addresses and configuration
    /// @param zkPayAddress Address of the deployed ZKPay contract
    /// @param config The configuration used for deployment
    /// @return formattedJson The formatted JSON string containing deployment information
    function _createFormattedOutputJson(address zkPayAddress, Config memory config)
        internal
        pure
        returns (string memory formattedJson)
    {
        // Create the deployedContracts section
        string memory deployedContracts = string.concat(
            "  \"deployedContracts\": {\n", "    \"ZKPay\": \"", _addressToString(zkPayAddress), "\"\n", "  }"
        );

        // Create the config section
        string memory configSection = string.concat(
            "  \"config\": {\n",
            "    \"zkpayAdmin\": \"",
            _addressToString(config.zkpayAdmin),
            "\",\n",
            "    \"usdcTokenAddress\": \"",
            _addressToString(config.usdcTokenAddress),
            "\",\n",
            "    \"usdcTokenPriceFeed\": \"",
            _addressToString(config.usdcTokenPriceFeed),
            "\",\n",
            "    \"router\": \"",
            _addressToString(config.router),
            "\",\n",
            "    \"usdt\": \"",
            _addressToString(config.usdt),
            "\"\n",
            "  }"
        );

        // Combine all sections
        formattedJson = string.concat("{\n", deployedContracts, ",\n", configSection, "\n}");
    }

    /// @notice Convert an address to its string representation
    /// @param addr The address to convert
    /// @return The string representation of the address
    function _addressToString(address addr) internal pure returns (string memory) {
        return vm.toString(addr);
    }
}
