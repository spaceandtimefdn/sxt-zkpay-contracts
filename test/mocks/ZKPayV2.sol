// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ZKPayStorage} from "../../src/ZKPayStorage.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @custom:oz-upgrades-from ZKPay
contract ZKPayV2 is ZKPayStorage, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
