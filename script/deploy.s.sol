// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/* solhint-disable no-console */
/* solhint-disable gas-small-strings */

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {PoSQLVerifier} from "../src/PoSQLVerifier.sol";
import {ClientContractExample} from "../test/mocks/ClientContractExample.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {SwapLogic} from "../src/libraries/SwapLogic.sol";

/// @title Deploy
/// @notice Deploy the ZKPay contract and PoSQLVerifier custom logic
/// @dev This script is used to deploy the ZKPay contract and PoSQLVerifier custom logic
/// @dev It also sets the USDC payment asset and deploys the ClientContractExample contract
contract Deploy is Script {
    using stdJson for string;

    /* solhint-disable gas-struct-packing */
    struct Config {
        // First slot: small integers packed together
        uint8 nativeTokenDecimals;
        uint8 usdcTokenDecimals;
        uint64 nativeTokenStalePriceThresholdInSeconds;
        uint64 usdcTokenStalePriceThresholdInSeconds;
        // Remaining slots: addresses (each takes a full slot)
        address zkpayOwner;
        address zkpayTreasury;
        address sxtTokenAddress;
        address nativeTokenPriceFeed;
        address posqlMerchantAddress;
        address usdcTokenAddress;
        address usdcTokenPriceFeed;
        address clientContractOwner;
        address router;
        address usdt;
        bytes defaultTargetAssetPath;
        bytes usdcToUsdtPath;
    }
    /* solhint-enable gas-struct-packing */

    function run() public {
        // Read the JSON file
        string memory configJson = vm.readFile(string.concat(vm.projectRoot(), "/script/input/config.json"));

        // Parse individual fields
        Config memory config;

        // zkpay section
        config.zkpayOwner = configJson.readAddress(".zkpayOwner");
        config.zkpayTreasury = configJson.readAddress(".zkpayTreasury");
        config.nativeTokenPriceFeed = configJson.readAddress(".nativeTokenPriceFeed");
        config.nativeTokenDecimals = uint8(configJson.readUint(".nativeTokenDecimals"));
        config.nativeTokenStalePriceThresholdInSeconds =
            uint64(configJson.readUint(".nativeTokenStalePriceThresholdInSeconds"));
        config.posqlMerchantAddress = configJson.readAddress(".posqlMerchantAddress");
        config.sxtTokenAddress = configJson.readAddress(".SXT");

        // usdc payment asset section
        config.usdcTokenAddress = configJson.readAddress(".usdcTokenAddress");
        config.usdcTokenPriceFeed = configJson.readAddress(".usdcTokenPriceFeed");
        config.usdcTokenDecimals = uint8(configJson.readUint(".usdcTokenDecimals"));
        config.usdcTokenStalePriceThresholdInSeconds =
            uint64(configJson.readUint(".usdcTokenStalePriceThresholdInSeconds"));

        // client contract section
        config.clientContractOwner = configJson.readAddress(".clientContractOwner");

        // swap logic section
        config.router = configJson.readAddress(".router");
        config.usdt = configJson.readAddress(".usdt");
        config.defaultTargetAssetPath = configJson.readBytes(".defaultTargetAssetPath");

        vm.startBroadcast();

        // Deploy ZKPay as a transparent proxy
        address zkPayProxy = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            msg.sender,
            abi.encodeCall(
                ZKPay.initialize,
                (
                    msg.sender,
                    config.zkpayTreasury,
                    config.sxtTokenAddress,
                    config.nativeTokenPriceFeed,
                    config.nativeTokenDecimals,
                    config.nativeTokenStalePriceThresholdInSeconds,
                    SwapLogic.SwapLogicConfig({
                        router: config.router,
                        usdt: config.usdt,
                        defaultTargetAssetPath: config.defaultTargetAssetPath
                    })
                )
            )
        );

        console.log("ZKPay proxy deployed at:", zkPayProxy);

        address zkPayImpl = Upgrades.getImplementationAddress(zkPayProxy);
        console.log("ZKPay implementation deployed at:", zkPayImpl);

        address zkPayAdmin = Upgrades.getAdminAddress(zkPayProxy);
        console.log("ZKPay proxy admin deployed at:", zkPayAdmin);

        // Set USDC payment asset
        ZKPay zkpay = ZKPay(zkPayProxy);
        AssetManagement.PaymentAsset memory usdcPaymentAsset = AssetManagement.PaymentAsset({
            allowedPaymentTypes: AssetManagement.SEND_PAYMENT_FLAG | AssetManagement.QUERY_PAYMENT_FLAG,
            priceFeed: config.usdcTokenPriceFeed,
            tokenDecimals: config.usdcTokenDecimals,
            stalePriceThresholdInSeconds: config.usdcTokenStalePriceThresholdInSeconds
        });
        zkpay.setPaymentAsset(config.usdcTokenAddress, usdcPaymentAsset, config.usdcToUsdtPath);

        // Deploy PoSQLVerifier
        address posqlVerifierCustomLogic = address(new PoSQLVerifier(config.posqlMerchantAddress));
        console.log("PoSQLVerifier custom logic deployed at:", posqlVerifierCustomLogic);

        // Deploy ClientContractExample
        address clientContract = address(new ClientContractExample(config.clientContractOwner));
        console.log("ClientContractExample deployed at:", clientContract);

        // set zkpay owner
        zkpay.transferOwnership(config.zkpayOwner);

        vm.stopBroadcast();

        // Create output JSON with deployed contract addresses
        string memory outputJson = _createFormattedOutputJson(
            zkPayProxy, zkPayImpl, zkPayAdmin, posqlVerifierCustomLogic, clientContract, config
        );

        // Write output to file
        string memory outputPath = string.concat(vm.projectRoot(), "/script/output/output.json");
        vm.writeFile(outputPath, outputJson);
        console.log("Deployment information written to:", outputPath);
    }

    /// @notice Create a formatted JSON output with deployed contract addresses and configuration
    /// @param zkPayProxy Address of the deployed ZKPay proxy contract
    /// @param zkPayImpl Address of the deployed ZKPay implementation contract
    /// @param zkPayAdmin Address of the deployed ZKPay proxy admin
    /// @param posqlVerifierCustomLogic Address of the deployed PoSQLVerifier custom logic
    /// @param config The configuration used for deployment
    /// @return formattedJson The formatted JSON string containing deployment information
    function _createFormattedOutputJson(
        address zkPayProxy,
        address zkPayImpl,
        address zkPayAdmin,
        address posqlVerifierCustomLogic,
        address clientContract,
        Config memory config
    ) internal pure returns (string memory formattedJson) {
        // Create the deployedContracts section
        string memory deployedContracts = string.concat(
            "  \"deployedContracts\": {\n",
            "    \"ZKPayProxy\": \"",
            _addressToString(zkPayProxy),
            "\",\n",
            "    \"ZKPayImplementation\": \"",
            _addressToString(zkPayImpl),
            "\",\n",
            "    \"ZKPayProxyAdmin\": \"",
            _addressToString(zkPayAdmin),
            "\",\n",
            "    \"PoSQLVerifierCustomLogic\": \"",
            _addressToString(posqlVerifierCustomLogic),
            "\",\n",
            "    \"ClientContractExample\": \"",
            _addressToString(clientContract),
            "\"\n",
            "  }"
        );

        // Create the deploymentConfig section
        string memory deploymentConfig = string.concat(
            "  \"deploymentConfig\": {\n",
            "    \"zkpayOwner\": \"",
            _addressToString(config.zkpayOwner),
            "\",\n",
            "    \"zkpayTreasury\": \"",
            _addressToString(config.zkpayTreasury),
            "\",\n",
            "    \"nativeTokenDecimals\": ",
            _uint8ToString(config.nativeTokenDecimals),
            ",\n",
            "    \"nativeTokenStalePriceThresholdInSeconds\": ",
            _uint64ToString(config.nativeTokenStalePriceThresholdInSeconds),
            ",\n",
            "    \"posqlMerchantAddress\": \"",
            _addressToString(config.posqlMerchantAddress),
            "\",\n",
            "    \"usdcTokenAddress\": \"",
            _addressToString(config.usdcTokenAddress),
            "\",\n",
            "    \"usdcTokenPriceFeed\": \"",
            _addressToString(config.usdcTokenPriceFeed),
            "\",\n",
            "    \"usdcTokenDecimals\": ",
            _uint8ToString(config.usdcTokenDecimals),
            ",\n",
            "    \"usdcTokenStalePriceThresholdInSeconds\": ",
            _uint64ToString(config.usdcTokenStalePriceThresholdInSeconds),
            ",\n",
            "    \"clientContractOwner\": \"",
            _addressToString(config.clientContractOwner),
            "\"\n",
            "  }"
        );

        // Combine all sections
        formattedJson = string.concat("{\n", deployedContracts, ",\n", deploymentConfig, "\n}");

        return formattedJson;
    }

    /// @notice Convert an address to a string
    /// @param addr The address to convert
    /// @return The string representation of the address
    function _addressToString(address addr) internal pure returns (string memory) {
        return _toLowerString(_toHexString(uint256(uint160(addr)), 20));
    }

    /// @notice Convert a uint8 to a string
    /// @param value The uint8 to convert
    /// @return The string representation of the uint8
    function _uint8ToString(uint8 value) internal pure returns (string memory) {
        return _toString(uint256(value));
    }

    /// @notice Convert a uint64 to a string
    /// @param value The uint64 to convert
    /// @return The string representation of the uint64
    function _uint64ToString(uint64 value) internal pure returns (string memory) {
        return _toString(uint256(value));
    }

    /// @notice Convert an int256 to a string
    /// @param value The int256 to convert
    /// @return The string representation of the int256
    function _int256ToString(int256 value) internal pure returns (string memory) {
        if (value < 0) {
            return string.concat("-", _toString(uint256(-value)));
        }
        return _toString(uint256(value));
    }

    /// @notice Convert a uint256 to a string
    /// @param value The uint256 to convert
    /// @return The string representation of the uint256
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            ++digits;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /// @notice Convert a uint256 to a hexadecimal string
    /// @param value The uint256 to convert
    /// @param length The length of the resulting hex string
    /// @return The hexadecimal string representation of the uint256
    function _toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";

        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _toHexChar(value & 0xf);
            value >>= 4;
        }

        return string(buffer);
    }

    /// @notice Convert a 4-bit value to its hexadecimal character representation
    /// @param value The 4-bit value to convert (0-15)
    /// @return The hexadecimal character
    function _toHexChar(uint256 value) internal pure returns (bytes1) {
        if (value < 10) {
            return bytes1(uint8(48 + value)); // 0-9
        } else {
            return bytes1(uint8(87 + value)); // a-f
        }
    }

    /// @notice Convert a string to lowercase
    /// @param str The string to convert
    /// @return The lowercase string
    function _toLowerString(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        uint256 length = bStr.length;
        for (uint256 i = 0; i < length; ++i) {
            // Convert uppercase to lowercase
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bStr[i] = bytes1(uint8(bStr[i]) + 32);
            }
        }
        return string(bStr);
    }
}
