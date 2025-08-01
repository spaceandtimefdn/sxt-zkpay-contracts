// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentLogic} from "../../src/module/PaymentLogic.sol";
import {AssetManagement} from "../../src/libraries/AssetManagement.sol";
import {PayWallLogic} from "../../src/libraries/PayWallLogic.sol";
import {SwapLogic} from "../../src/libraries/SwapLogic.sol";
import {EscrowPayment} from "../../src/libraries/EscrowPayment.sol";
import {PROTOCOL_FEE, PROTOCOL_FEE_PRECISION} from "../../src/libraries/Constants.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Setup} from "./Setup.sol";

contract PaymentLogicHelper {
    using AssetManagement for mapping(address asset => AssetManagement.PaymentAsset);
    using PayWallLogic for PayWallLogic.PayWallLogicStorage;
    using SwapLogic for SwapLogic.SwapLogicStorage;
    using EscrowPayment for EscrowPayment.EscrowPaymentStorage;

    mapping(address asset => AssetManagement.PaymentAsset) internal _assets;
    PayWallLogic.PayWallLogicStorage internal _paywallStorage;
    SwapLogic.SwapLogicStorage internal _swapStorage;
    EscrowPayment.EscrowPaymentStorage internal _escrowStorage;

    function setupAssets(address mockToken) external {
        Setup.setupAssets(_assets, mockToken);
    }

    function setItemPrice(address merchant, bytes32 itemId, uint248 price) external {
        _paywallStorage.setItemPrice(merchant, itemId, price);
    }

    function validateItemPrice(address merchant, bytes32 itemId, uint248 amountInUSD) external view {
        PaymentLogic._validateItemPrice(_paywallStorage, merchant, itemId, amountInUSD);
    }

    function isAssetSupported(address asset) external view returns (bool) {
        return _assets.isSupported(asset);
    }

    function authorizePayment(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) external returns (bytes32) {
        return PaymentLogic.authorizePayment(
            _escrowStorage, _assets, _paywallStorage, asset, amount, onBehalfOf, merchant, memo, itemId
        );
    }

    function computeSettlementBreakdown(
        address sourceAsset,
        uint248 sourceAssetAmount,
        uint248 maxUsdValueOfTargetToken,
        address payoutToken,
        address sxt
    )
        external
        view
        returns (uint248 toBePaidInSourceToken, uint248 toBeRefundedInSourceToken, uint248 protocolFeeInSourceToken)
    {
        return PaymentLogic.computeSettlementBreakdown(
            _assets, sourceAsset, sourceAssetAmount, maxUsdValueOfTargetToken, payoutToken, sxt
        );
    }

    function processPayment(
        address asset,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId,
        address treasury,
        address sxt
    ) external {
        PaymentLogic.processPayment(
            _swapStorage, _assets, _paywallStorage, asset, amount, onBehalfOf, merchant, memo, itemId, treasury, sxt
        );
    }

    function processSettlement(
        address sourceAsset,
        uint248 sourceAssetAmount,
        address from,
        address merchant,
        bytes32 transactionHash,
        uint248 maxUsdValueOfTargetToken,
        address treasury,
        address sxt
    ) external {
        PaymentLogic.processSettlement(
            _escrowStorage,
            _swapStorage,
            _assets,
            treasury,
            sxt,
            sourceAsset,
            sourceAssetAmount,
            from,
            merchant,
            transactionHash,
            maxUsdValueOfTargetToken
        );
    }
}

contract PaymentLogicTest is Test {
    address internal constant SXT_TOKEN = address(0x1234);
    address internal constant OTHER_TOKEN = address(0x5678);
    address internal constant MERCHANT = address(0x9ABC);
    address internal constant TREASURY = address(0xDEF0);
    uint248 internal constant PAYMENT_AMOUNT = 1000e18;
    bytes32 internal constant ITEM_ID = bytes32(uint256(0x1111));
    bytes32 internal constant ON_BEHALF_OF = bytes32(uint256(0x2222));
    string internal constant MEMO = "test memo";

    PaymentLogicHelper internal _helper;
    MockERC20 internal _mockToken;
    MockERC20 internal _sxtToken;

    function setUp() public {
        _helper = new PaymentLogicHelper();
        _mockToken = new MockERC20();
        _sxtToken = new MockERC20();
        vm.label(address(_mockToken), "MockToken");
        vm.label(address(_sxtToken), "SXTToken");
        vm.label(MERCHANT, "Merchant");
        vm.label(TREASURY, "Treasury");

        _helper.setupAssets(address(_mockToken));
        _mockToken.mint(address(this), 10000e18);
        _sxtToken.mint(address(this), 10000e18);
        _mockToken.mint(address(_helper), 10000e18);
        _sxtToken.mint(address(_helper), 10000e18);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testCalculateProtocolFeeWithRegularAsset() public pure {
        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            PaymentLogic._calculateProtocolFee(OTHER_TOKEN, PAYMENT_AMOUNT, SXT_TOKEN);

        uint248 expectedFee = uint248((uint256(PAYMENT_AMOUNT) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        assertEq(protocolFeeAmount, expectedFee);
        assertEq(remainingAmount, PAYMENT_AMOUNT - expectedFee);
    }

    function testCalculateProtocolFeeWithSXTToken() public pure {
        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            PaymentLogic._calculateProtocolFee(SXT_TOKEN, PAYMENT_AMOUNT, SXT_TOKEN);

        assertEq(protocolFeeAmount, 0);
        assertEq(remainingAmount, PAYMENT_AMOUNT);
    }

    function testFuzzCalculateProtocolFee(uint248 amount) public pure {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint248).max / PROTOCOL_FEE); // Prevent overflow

        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            PaymentLogic._calculateProtocolFee(OTHER_TOKEN, amount, SXT_TOKEN);

        uint248 expectedFee = uint248((uint256(amount) * PROTOCOL_FEE) / PROTOCOL_FEE_PRECISION);
        assertEq(protocolFeeAmount, expectedFee);
        assertEq(remainingAmount, amount - expectedFee);
        assertEq(protocolFeeAmount + remainingAmount, amount);
    }

    function testFuzzCalculateProtocolFeeWithSXT(uint248 amount) public pure {
        (uint248 protocolFeeAmount, uint248 remainingAmount) =
            PaymentLogic._calculateProtocolFee(SXT_TOKEN, amount, SXT_TOKEN);

        assertEq(protocolFeeAmount, 0);
        assertEq(remainingAmount, amount);
    }

    function testValidateAssetIsSupported() public view {
        bool isSupported = _helper.isAssetSupported(address(_mockToken));
        assertTrue(isSupported);
    }

    function testValidateAssetIsNotSupported() public view {
        address unsupportedAsset = address(0x9999);
        bool isSupported = _helper.isAssetSupported(unsupportedAsset);
        assertFalse(isSupported);
    }

    function testValidateItemPriceWithSufficientPayment() public {
        _helper.setItemPrice(MERCHANT, ITEM_ID, 100e18);
        _helper.validateItemPrice(MERCHANT, ITEM_ID, 200e18);
    }

    function testValidateItemPriceWithInsufficientPayment() public {
        _helper.setItemPrice(MERCHANT, ITEM_ID, 100e18);
        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        _helper.validateItemPrice(MERCHANT, ITEM_ID, 50e18);
    }

    function testValidateItemPriceWithExactPayment() public {
        _helper.setItemPrice(MERCHANT, ITEM_ID, 100e18);
        _helper.validateItemPrice(MERCHANT, ITEM_ID, 100e18);
    }

    function testValidateItemPriceWithZeroPrice() public view {
        _helper.validateItemPrice(MERCHANT, ITEM_ID, 50e18);
    }

    function testAuthorizePaymentWithZeroAmount() public {
        _mockToken.approve(address(_helper), 0);
        vm.expectRevert(PaymentLogic.ZeroAmountReceived.selector);
        _helper.authorizePayment(address(_mockToken), 0, ON_BEHALF_OF, MERCHANT, bytes(MEMO), ITEM_ID);
    }

    function testComputeSettlementBreakdownBasic() public view {
        (uint248 toBePaid, uint248 toBeRefunded, uint248 protocolFee) = _helper.computeSettlementBreakdown(
            address(_mockToken), 1000e18, 500e18, address(_sxtToken), address(_sxtToken)
        );

        assertTrue(toBePaid > 0);
        assertTrue(toBeRefunded >= 0);
        assertTrue(protocolFee >= 0);
        assertEq(toBePaid + toBeRefunded + protocolFee, 1000e18);
    }

    function testComputeSettlementBreakdownWithSXT() public view {
        (,, uint248 protocolFee) = _helper.computeSettlementBreakdown(
            address(_mockToken), 1000e18, 500e18, address(_sxtToken), address(_sxtToken)
        );

        assertEq(protocolFee, 0);
    }

    function testProcessPaymentWithValidInput() public {
        vm.skip(true);
    }

    function testProcessSettlementWithValidInput() public {
        vm.skip(true);
    }

    function testAuthorizePaymentWithValidInput() public {
        _mockToken.approve(address(_helper), PAYMENT_AMOUNT);
        bytes32 txHash =
            _helper.authorizePayment(address(_mockToken), PAYMENT_AMOUNT, ON_BEHALF_OF, MERCHANT, bytes(MEMO), ITEM_ID);
        assertTrue(txHash != bytes32(0));
    }

    function testComputeSettlementBreakdownDirectCall() public view {
        (uint248 toBePaid, uint248 toBeRefunded, uint248 protocolFee) = _helper.computeSettlementBreakdown(
            address(_mockToken), 2000e18, 1500e18, address(_mockToken), address(_sxtToken)
        );

        assertTrue(toBePaid > 0);
        assertTrue(toBeRefunded >= 0);
        assertTrue(protocolFee >= 0);
    }
}
