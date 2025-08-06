// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {MerchantLogic} from "../../src/libraries/MerchantLogic.sol";
import {SwapLogic} from "../../src/libraries/SwapLogic.sol";
import {PayWallLogic} from "../../src/libraries/PayWallLogic.sol";
import {EscrowPayment} from "../../src/libraries/EscrowPayment.sol";

/// @custom:oz-upgrades-from ZKPay
contract ZKPayV2 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // solhint-disable-next-line gas-struct-packing
    struct ZKPayStorage {
        address sxt;
        address treasury;
        address executorAddress;
        mapping(address asset => AssetManagement.PaymentAsset) assets;
        mapping(address merchantAddress => MerchantLogic.MerchantConfig merchantConfig) merchantConfigs;
        SwapLogic.SwapLogicStorage swapLogicStorage;
        PayWallLogic.PayWallLogicStorage paywallLogicStorage;
        EscrowPayment.EscrowPaymentStorage escrowPaymentStorage;
    }

    ZKPayStorage internal _zkPayStorage;
    uint256 public constant VERSION = 2;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external reinitializer(2) {
        __Ownable_init(owner);
        __ReentrancyGuard_init();
    }

    /// @notice Returns the version of the contract
    function getVersion() external pure returns (uint256 version) {
        return VERSION;
    }
}
