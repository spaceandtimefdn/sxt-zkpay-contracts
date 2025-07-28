// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/* solhint-disable no-console */
/* solhint-disable gas-small-strings */

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
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
        address zkpayOwner;
        address zkpayTreasury;
        address sxtTokenAddress;
        address usdcTokenAddress;
        address usdcTokenPriceFeed;
        address router;
        address usdt;
        bytes defaultTargetAssetPath;
        bytes usdcToUsdtPath;
    }
    /* solhint-enable gas-struct-packing */

    function run() external {
        // Read configuration from JSON file
        Config memory config = _readConfig();

        // Deploy contracts
        vm.startBroadcast();

        // Deploy ZKPay proxy
        address zkPayProxy = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            config.zkpayTreasury,
            abi.encodeCall(
                ZKPay.initialize,
                (
                    config.zkpayTreasury,
                    config.zkpayTreasury,
                    config.sxtTokenAddress,
                    SwapLogic.SwapLogicConfig({
                        router: config.router,
                        usdt: config.usdt,
                        defaultTargetAssetPath: config.defaultTargetAssetPath
                    })
                )
            )
        );

        address zkPayImpl = Upgrades.getImplementationAddress(zkPayProxy);
        address zkPayAdmin = Upgrades.getAdminAddress(zkPayProxy);

        console.log("ZKPay proxy deployed at:", zkPayProxy);
        console.log("ZKPay implementation deployed at:", zkPayImpl);
        console.log("ZKPay admin deployed at:", zkPayAdmin);

        // Set USDC payment asset
        ZKPay zkpay = ZKPay(zkPayProxy);
        AssetManagement.PaymentAsset memory usdcPaymentAsset = AssetManagement.PaymentAsset({
            priceFeed: config.usdcTokenPriceFeed,
            tokenDecimals: config.usdcTokenDecimals,
            stalePriceThresholdInSeconds: config.usdcTokenStalePriceThresholdInSeconds
        });
        zkpay.setPaymentAsset(config.usdcTokenAddress, usdcPaymentAsset, config.usdcToUsdtPath);

        // set zkpay owner
        zkpay.transferOwnership(config.zkpayOwner);

        vm.stopBroadcast();

        // Create output JSON with deployed contract addresses
        string memory outputJson = _createFormattedOutputJson(zkPayProxy, zkPayImpl, zkPayAdmin, config);

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
        config.zkpayOwner = configJson.readAddress(".zkpayOwner");
        config.zkpayTreasury = configJson.readAddress(".zkpayTreasury");

        config.sxtTokenAddress = configJson.readAddress(".SXT");

        // usdc payment asset section
        config.usdcTokenAddress = configJson.readAddress(".usdcTokenAddress");
        config.usdcTokenPriceFeed = configJson.readAddress(".usdcTokenPriceFeed");
        config.usdcTokenDecimals = uint8(configJson.readUint(".usdcTokenDecimals"));
        config.usdcTokenStalePriceThresholdInSeconds =
            uint64(configJson.readUint(".usdcTokenStalePriceThresholdInSeconds"));

        // swap logic section
        config.router = configJson.readAddress(".router");
        config.usdt = configJson.readAddress(".usdt");
        config.defaultTargetAssetPath = configJson.readBytes(".defaultTargetAssetPath");
        config.usdcToUsdtPath = configJson.readBytes(".usdcToUsdtPath");
    }

    /// @notice Create a formatted JSON output with deployed contract addresses and configuration
    /// @param zkPayProxy Address of the deployed ZKPay proxy contract
    /// @param zkPayImpl Address of the deployed ZKPay implementation contract
    /// @param zkPayAdmin Address of the deployed ZKPay proxy admin
    /// @param config The configuration used for deployment
    /// @return formattedJson The formatted JSON string containing deployment information
    function _createFormattedOutputJson(address zkPayProxy, address zkPayImpl, address zkPayAdmin, Config memory config)
        internal
        pure
        returns (string memory formattedJson)
    {
        // Create the deployedContracts section
        string memory deployedContracts = string.concat(
            "  \"deployedContracts\": {\n",
            "    \"ZKPayProxy\": \"",
            _addressToString(zkPayProxy),
            "\",\n",
            "    \"ZKPayImplementation\": \"",
            _addressToString(zkPayImpl),
            "\",\n",
            "    \"ZKPayAdmin\": \"",
            _addressToString(zkPayAdmin),
            "\"\n",
            "  }"
        );

        // Create the config section
        string memory configSection = string.concat(
            "  \"config\": {\n",
            "    \"zkpayOwner\": \"",
            _addressToString(config.zkpayOwner),
            "\",\n",
            "    \"zkpayTreasury\": \"",
            _addressToString(config.zkpayTreasury),
            "\",\n",
            "    \"sxtTokenAddress\": \"",
            _addressToString(config.sxtTokenAddress),
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
