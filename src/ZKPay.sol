// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {ZKPayStorage} from "./ZKPayStorage.sol";
import {IZKPay} from "./interfaces/IZKPay.sol";
import {AssetManagement} from "./libraries/AssetManagement.sol";
import {MerchantLogic} from "./libraries/MerchantLogic.sol";
import {ZERO_ADDRESS} from "./libraries/Constants.sol";
import {SwapLogic} from "./libraries/SwapLogic.sol";
import {PayWallLogic} from "./libraries/PayWallLogic.sol";
import {SafeExecutor} from "./SafeExecutor.sol";
import {IMerchantCallback} from "./interfaces/IMerchantCallback.sol";
import {EscrowPayment} from "./libraries/EscrowPayment.sol";

// slither-disable-next-line locked-ether
contract ZKPay is ZKPayStorage, IZKPay, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using MerchantLogic for mapping(address merchant => MerchantLogic.MerchantConfig);
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using EscrowPayment for EscrowPayment.EscrowPaymentStorage;

    error TreasuryAddressCannotBeZero();
    error TreasuryAddressSameAsCurrent();
    error SXTAddressCannotBeZero();
    error InsufficientPayment();
    error ExecutorAddressCannotBeZero();
    error InvalidMerchant();
    error ZeroAmountReceived();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        address treasury,
        address sxt,
        SwapLogic.SwapLogicConfig calldata swapLogicConfig
    ) external initializer {
        __Ownable_init(owner);
        __ReentrancyGuard_init();
        _setTreasury(treasury);
        _setSXT(sxt);
        _deployExecutor();

        _swapLogicStorage.setConfig(swapLogicConfig);
    }

    function _deployExecutor() internal {
        _executorAddress = address(new SafeExecutor());
    }

    function _setSXT(address sxt) internal {
        if (sxt == ZERO_ADDRESS) {
            revert SXTAddressCannotBeZero();
        }
        _sxt = sxt;
    }

    function _setTreasury(address treasury) internal {
        if (treasury == ZERO_ADDRESS) {
            revert TreasuryAddressCannotBeZero();
        }

        if (treasury == _treasury) {
            revert TreasuryAddressSameAsCurrent();
        }

        _treasury = treasury;
        emit TreasurySet(treasury);
    }

    /// @inheritdoc IZKPay
    function setTreasury(address treasury) external onlyOwner {
        _setTreasury(treasury);
    }

    /// @inheritdoc IZKPay
    function getTreasury() external view returns (address treasury) {
        return _treasury;
    }

    /// @inheritdoc IZKPay
    function getSXT() external view returns (address sxt) {
        return _sxt;
    }

    /// @inheritdoc IZKPay
    function getExecutorAddress() external view returns (address executor) {
        return _executorAddress;
    }

    /// @inheritdoc IZKPay
    function setPaymentAsset(
        address assetAddress,
        AssetManagement.PaymentAsset calldata paymentAsset,
        bytes calldata path
    ) external onlyOwner {
        address originAsset = SwapLogic.calldataExtractPathOriginAsset(path);
        if (originAsset != assetAddress) {
            revert SwapLogic.InvalidPath();
        }

        AssetManagement.set(_assets, assetAddress, paymentAsset);
        _swapLogicStorage.setSourceAssetPath(path);
    }

    /// @inheritdoc IZKPay
    function removePaymentAsset(address asset) external onlyOwner {
        AssetManagement.remove(_assets, asset);
    }

    /// @inheritdoc IZKPay
    function getPaymentAsset(address asset) external view returns (AssetManagement.PaymentAsset memory paymentAsset) {
        return AssetManagement.get(_assets, asset);
    }

    function _validateMerchant(address merchant, address callbackContractAddress) internal view {
        address callbackContractMerchant = IMerchantCallback(callbackContractAddress).getMerchant();
        if (callbackContractMerchant != merchant) {
            revert InvalidMerchant();
        }
    }

    function _validateItemPrice(address merchant, bytes32 itemId, uint248 amountInUSD) internal view {
        uint248 itemPrice = _paywallLogicStorage.getItemPrice(merchant, itemId);
        if (amountInUSD < itemPrice) {
            revert InsufficientPayment();
        }
    }

    function _sendPayment(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) internal {
        (uint248 actualAmountReceived, uint248 amountInUSD, uint248 protocolFeeAmount) =
            _assets.send(asset, amount, merchant, _treasury, _sxt);

        _validateItemPrice(merchant, itemId, amountInUSD);

        emit SendPayment(
            asset, actualAmountReceived, protocolFeeAmount, onBehalfOf, merchant, memo, amountInUSD, msg.sender, itemId
        );
    }

    /// @inheritdoc IZKPay
    function send(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external nonReentrant {
        _sendPayment(asset, amount, onBehalfOf, merchant, memo, itemId);
    }

    /// @inheritdoc IZKPay
    function sendWithCallback(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        address callbackContractAddress,
        bytes calldata callbackData
    ) external nonReentrant {
        bytes4 selector = bytes4(callbackData[:4]);
        bytes32 itemId = keccak256(abi.encode(callbackContractAddress, selector));
        _sendPayment(asset, amount, onBehalfOf, merchant, memo, itemId);
        _validateMerchant(merchant, callbackContractAddress);

        SafeExecutor(_executorAddress).execute(callbackContractAddress, callbackData);
    }

    /// @inheritdoc IZKPay
    function authorize(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external nonReentrant returns (bytes32 transactionHash) {
        (uint248 actualAmountReceived, uint248 amountInUSD) = _assets.escrowPayment(asset, amount);

        if (actualAmountReceived == 0) {
            revert ZeroAmountReceived();
        }

        _validateItemPrice(merchant, itemId, amountInUSD);

        EscrowPayment.Transaction memory transaction =
            EscrowPayment.Transaction({asset: asset, amount: actualAmountReceived, from: msg.sender, to: merchant});

        transactionHash = EscrowPayment.authorize(_escrowPaymentStorage, transaction);

        emit Authorized(transaction, transactionHash, onBehalfOf, memo, itemId);
    }

    /// @inheritdoc IZKPay
    function setMerchantConfig(MerchantLogic.MerchantConfig calldata config, bytes calldata path) external {
        _merchantConfigs.set(msg.sender, config);
        _swapLogicStorage.setMerchantTargetAssetPath(msg.sender, path);
    }

    /// @inheritdoc IZKPay
    function getMerchantConfig(address merchant) external view returns (MerchantLogic.MerchantConfig memory config) {
        return _merchantConfigs.get(merchant);
    }

    /// @inheritdoc IZKPay
    function setPaywallItemPrice(bytes32 item, uint248 price) external {
        _paywallLogicStorage.setItemPrice(msg.sender, item, price);
    }

    /// @inheritdoc IZKPay
    function getPaywallItemPrice(bytes32 item, address merchant) external view returns (uint248 price) {
        return _paywallLogicStorage.getItemPrice(merchant, item);
    }
}
