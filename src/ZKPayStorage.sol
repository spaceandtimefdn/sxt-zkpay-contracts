// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagement} from "./libraries/AssetManagement.sol";
import {MerchantLogic} from "./libraries/MerchantLogic.sol";
import {SwapLogic} from "./libraries/SwapLogic.sol";
import {PayWallLogic} from "./libraries/PayWallLogic.sol";
import {EscrowPayment} from "./libraries/EscrowPayment.sol";

contract ZKPayStorage {
    address internal _treasury;
    mapping(address asset => AssetManagement.PaymentAsset) internal _assets;
    mapping(address merchantAddress => MerchantLogic.MerchantConfig merchantConfig) internal _merchantConfigs;

    address internal _sxt;

    // **  Swap Logic Storage ** //
    SwapLogic.SwapLogicStorage internal _swapLogicStorage;
    // **  Paywall Logic Storage ** //
    PayWallLogic.PayWallLogicStorage internal _paywallLogicStorage;

    // **  Escrow Payment Storage ** //
    EscrowPayment.EscrowPaymentStorage internal _escrowPaymentStorage;

    address public _executorAddress;
}
