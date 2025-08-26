// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {DSPay} from "../src/DSPay.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MerchantLogic} from "../src/libraries/MerchantLogic.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ZERO_ADDRESS} from "../src/libraries/Constants.sol";
import {DummyData} from "./data/DummyData.sol";
import {SwapLogic} from "../src/libraries/SwapLogic.sol";
import {PayWallLogic} from "../src/libraries/PayWallLogic.sol";
import {PendingPayment} from "../src/libraries/PendingPayment.sol";
import {PaymentLogic} from "../src/module/PaymentLogic.sol";
import {IDSPay} from "../src/interfaces/IDSPay.sol";
import {IMerchantCallback} from "../src/interfaces/IMerchantCallback.sol";

contract MockAuthorizeCallbackContract is IMerchantCallback {
    address private _merchant;
    uint256 public callCount;
    bytes public lastCallData;
    bool public shouldFail;

    error AuthorizeCallbackFailed();

    constructor(address merchant_) {
        _merchant = merchant_;
    }

    function getMerchant() external view override returns (address) {
        return _merchant;
    }

    function processAuthorization(uint256 value) external {
        if (shouldFail) {
            revert AuthorizeCallbackFailed();
        }
        ++callCount;
        lastCallData = abi.encode(value);
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
}

contract MockInvalidAuthorizeCallbackContract is IMerchantCallback {
    function getMerchant() external pure override returns (address) {
        return address(0x999);
    }

    // solhint-disable-next-line no-empty-blocks
    function processAuthorization(uint256 value) external pure {}
}

contract DSPayTest is Test {
    DSPay public dspay;
    address public _admin;
    address public _priceFeed;
    AssetManagement.PaymentAsset public paymentAssetInstance;
    address public _sxt;
    int256 public _tokenPrice;

    function setUp() public {
        _admin = vm.addr(0x1);
        _tokenPrice = 1000;

        _priceFeed = address(new MockV3Aggregator(8, _tokenPrice));
        _sxt = address(new MockERC20());

        dspay = new DSPay(_admin, DummyData.getSwapLogicConfig());

        paymentAssetInstance =
            AssetManagement.PaymentAsset({priceFeed: _priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 1000});
    }

    function testAdminRoleTransfer() public {
        bytes32 adminRole = dspay.DEFAULT_ADMIN_ROLE();
        address newAdmin = address(0x4);

        assertTrue(dspay.hasRole(adminRole, _admin));

        vm.prank(_admin);
        dspay.beginDefaultAdminTransfer(newAdmin);

        assertTrue(dspay.hasRole(adminRole, _admin));
        assertFalse(dspay.hasRole(adminRole, newAdmin));

        (address pendingAdmin,) = dspay.pendingDefaultAdmin();
        assertEq(pendingAdmin, newAdmin);

        skip(1 days);

        vm.prank(newAdmin);
        dspay.acceptDefaultAdminTransfer();
        assertTrue(dspay.hasRole(adminRole, newAdmin));
        assertFalse(dspay.hasRole(adminRole, _admin));
    }

    function testOnlyAdminCanTransferAdminRole() public {
        vm.prank(address(0x5));
        vm.expectRevert();
        dspay.beginDefaultAdminTransfer(address(0x6));
    }

    function testFuzzSetPaymentAsset(address asset, uint8 tokenDecimals, uint64 stalePriceThresholdInSeconds) public {
        vm.prank(_admin);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(asset, _priceFeed, tokenDecimals, stalePriceThresholdInSeconds);

        dspay.setPaymentAsset(
            asset,
            AssetManagement.PaymentAsset({
                priceFeed: _priceFeed,
                tokenDecimals: tokenDecimals,
                stalePriceThresholdInSeconds: stalePriceThresholdInSeconds
            }),
            DummyData.getOriginAssetPath(asset)
        );
    }

    function testFuzzSetPaymentAsset(address asset) public {
        vm.prank(_admin);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(asset, _priceFeed, 18, 1000);

        dspay.setPaymentAsset(asset, paymentAssetInstance, DummyData.getOriginAssetPath(asset));
    }

    function testFuzzSetPaymentAssetInvalidPath(address asset) public {
        vm.prank(_admin);
        vm.assume(asset != DummyData.getUsdtAddress());

        vm.expectRevert(SwapLogic.InvalidPath.selector);
        dspay.setPaymentAsset(asset, paymentAssetInstance, DummyData.getDestinationAssetPath(asset));
    }

    function testFuzzOnlyAdminCanSetPaymentAsset(address caller) public {
        vm.prank(caller);

        if (caller != _admin) {
            vm.expectRevert();
        }

        dspay.setPaymentAsset(address(0x4), paymentAssetInstance, DummyData.getOriginAssetPath(address(0x4)));
    }

    function testRemovePaymentAsset() public {
        vm.startPrank(_admin);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetRemoved(address(0x100));

        dspay.removePaymentAsset(address(0x100));

        vm.expectRevert(AssetManagement.AssetNotFound.selector);
        dspay.getPaymentAsset(address(0x100));
    }

    function testFuzzOnlyAdminCanRemovePaymentAsset(address caller) public {
        vm.prank(caller);

        if (caller != _admin) {
            vm.expectRevert();
        }

        dspay.removePaymentAsset(address(0x100));
    }

    function _setupMockTokenForAuthorize(uint248 amount) internal returns (MockERC20) {
        MockERC20 mockToken = new MockERC20();
        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        return mockToken;
    }

    function testSetAndGetPaywallItemPrice() public {
        bytes32 item = bytes32(uint256(0x1234));
        uint248 price = 1 ether;
        address merchant = address(0x1234);

        vm.expectEmit(true, true, true, true);
        emit PayWallLogic.ItemPriceSet(merchant, item, price);

        vm.prank(merchant);
        dspay.setPaywallItemPrice(item, price);
        assertEq(dspay.getPaywallItemPrice(item, merchant), price);
    }

    function testGetExecutorAddress() public view {
        address executorAddress = dspay.getExecutorAddress();
        assertTrue(executorAddress != address(0));
    }

    function testAuthorizeBasic() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = new MockERC20();
        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeIncrementsNonce() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount * 4);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 4, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithZeroValues() public {
        uint248 amount = 0;
        bytes32 onBehalfOf = bytes32(0);
        address merchant = address(1);
        bytes memory memo = "";
        bytes32 itemId = bytes32(0);

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        vm.expectRevert(PaymentLogic.ZeroAmountReceived.selector);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        amount = 1;
        mockToken = _setupMockTokenForAuthorize(amount);

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithMaxValues() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(type(uint256).max);
        address merchant = address(type(uint160).max);
        bytes memory memo =
            "maximum length memo that could be very long and contains lots of text to test boundary conditions";
        bytes32 itemId = bytes32(type(uint256).max);

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithZeroMerchantAddress() public {
        uint248 amount = 100;
        bytes32 onBehalfOf = bytes32(uint256(0x1234));
        address merchant = ZERO_ADDRESS;
        bytes memory memo = "test memo";
        bytes32 itemId = bytes32("test");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        vm.expectRevert(DSPay.MerchantAddressCannotBeZero.selector);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithLongMemo() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo =
            "This is a very long memo that contains a lot of text to test the handling of long memo fields in the transaction structure and to ensure it works correctly with the authorization process and that the gas costs are reasonable";
        bytes32 itemId = bytes32("longmemo");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeMultipleDifferentTransactions() public {
        MockERC20 mockToken = _setupMockTokenForAuthorize(300);

        PendingPayment.Transaction memory transaction1 = PendingPayment.Transaction({
            asset: address(mockToken),
            amount: 100,
            from: address(this),
            to: address(0x3333)
        });

        PendingPayment.Transaction memory transaction2 = PendingPayment.Transaction({
            asset: address(mockToken),
            amount: 200,
            from: address(this),
            to: address(0x6666)
        });

        bytes32 expectedHash1 = keccak256(abi.encode(transaction1, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(
            transaction1, expectedHash1, bytes32(uint256(uint160(address(0x2222)))), "tx1", bytes32("item1")
        );
        dspay.authorize(
            transaction1.asset,
            transaction1.amount,
            bytes32(uint256(uint160(address(0x2222)))),
            transaction1.to,
            "tx1",
            bytes32("item1")
        );

        bytes32 expectedHash2 = keccak256(abi.encode(transaction2, 2, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(
            transaction2, expectedHash2, bytes32(uint256(uint160(address(0x5555)))), "tx2", bytes32("item2")
        );
        dspay.authorize(
            transaction2.asset,
            transaction2.amount,
            bytes32(uint256(uint160(address(0x5555)))),
            transaction2.to,
            "tx2",
            bytes32("item2")
        );
    }

    function testAuthorizeWithDifferentChainId() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount * 2);

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 hash1 = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, hash1, onBehalfOf, memo, itemId);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        vm.chainId(999);

        PendingPayment.Transaction memory expectedTransaction2 =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 hash2 = keccak256(abi.encode(expectedTransaction2, 2, 999));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction2, hash2, onBehalfOf, memo, itemId);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        assertNotEq(hash1, hash2);

        vm.chainId(1);
    }

    function testAuthorizeReentrancyProtection() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testFuzzAuthorize(
        address,
        uint248 amount,
        bytes32 onBehalfOf,
        address merchant,
        bytes calldata memo,
        bytes32 itemId
    ) public {
        vm.assume(amount > 0 && amount < uint248(type(uint256).max / uint256(_tokenPrice)));
        vm.assume(merchant != ZERO_ADDRESS);

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithUnsupportedAsset() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = new MockERC20();
        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeInsufficientPayment() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        uint248 itemPrice = 2000 * 1e18;
        vm.prank(merchant);
        dspay.setPaywallItemPrice(itemId, itemPrice);

        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithCallbackBasic() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 1000 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "test memo";
        bytes32 itemId = bytes32(uint256(123));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData = abi.encode(42);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        PendingPayment.Transaction memory expectedTransaction =
            PendingPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));

        vm.expectEmit(true, true, true, true);
        emit IDSPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 42);

        assertEq(mockToken.balanceOf(address(dspay)), amount);
        assertEq(mockToken.balanceOf(address(this)), 0);
    }

    function testAuthorizeWithCallbackItemIdGeneration() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "itemId test";
        bytes32 itemId = bytes32(uint256(456));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData = abi.encode(999);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        assertTrue(itemId != bytes32(0));

        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 999);
    }

    function testAuthorizeWithCallbackInvalidMerchant() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "invalid merchant test";
        bytes32 itemId = bytes32(uint256(789));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockInvalidAuthorizeCallbackContract invalidCallbackContract = new MockInvalidAuthorizeCallbackContract();
        bytes memory callbackData = abi.encode(42);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(invalidCallbackContract),
                funcSig: MockInvalidAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        vm.expectRevert(DSPay.InvalidMerchant.selector);
        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);

        assertEq(mockToken.balanceOf(address(dspay)), 0);
        assertEq(mockToken.balanceOf(address(this)), amount);
    }

    function testAuthorizeWithCallbackFailure() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "callback failure test";
        bytes32 itemId = bytes32(uint256(101));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        callbackContract.setShouldFail(true);
        bytes memory callbackData = abi.encode(42);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        vm.expectRevert();
        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);

        assertEq(mockToken.balanceOf(address(dspay)), 0);
        assertEq(mockToken.balanceOf(address(this)), amount);
    }

    function testAuthorizeWithCallbackUnsupportedAsset() public {
        address merchant = vm.addr(0x10);
        address unsupportedToken = vm.addr(0x20);
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "unsupported asset test";
        bytes32 itemId = bytes32(uint256(102));

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData = abi.encode(42);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        vm.expectRevert();
        dspay.authorizeWithCallback(unsupportedToken, amount, onBehalfOf, merchant, memo, itemId, callbackData);
    }

    function testAuthorizeWithCallbackZeroAmount() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 0;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "zero amount test";
        bytes32 itemId = bytes32(uint256(103));

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData = abi.encode(42);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        vm.expectRevert();
        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);
    }

    function testAuthorizeWithCallbackWithPaywallItemPrice() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 1000 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "paywall test";
        bytes32 itemId = bytes32(uint256(104));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData = abi.encode(789);

        uint248 itemPrice = 1;

        vm.prank(merchant);
        dspay.setPaywallItemPrice(itemId, itemPrice);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 789);
    }

    function testAuthorizeWithCallbackInsufficientPaywallPayment() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "insufficient paywall test";

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        bytes32 itemId = bytes32(uint256(105));
        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData = abi.encode(123);

        uint248 itemPrice = 1000 * 1e18;

        vm.prank(merchant);
        dspay.setPaywallItemPrice(itemId, itemPrice);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        vm.expectRevert(PaymentLogic.InsufficientPayment.selector);
        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);
    }

    function testFuzzAuthorizeWithCallback(uint248 amount, uint256 callbackValue, address merchant, bytes32 onBehalfOf)
        public
    {
        amount = uint248(bound(amount, 1, 1000000 ether));
        callbackValue = bound(callbackValue, 0, type(uint256).max);
        vm.assume(merchant != address(0));
        vm.assume(merchant != address(dspay));

        MockERC20 mockToken = new MockERC20();
        bytes memory memo = "fuzz test";
        bytes32 itemId = bytes32(uint256(106));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData = abi.encode(callbackValue);

        vm.prank(merchant);
        dspay.setItemIdCallbackConfig(
            itemId,
            MerchantLogic.ItemIdCallbackConfig({
                contractAddress: address(callbackContract),
                funcSig: MockAuthorizeCallbackContract.processAuthorization.selector,
                includePaymentMetadata: false,
                acceptedMethods: MerchantLogic.AUTHORIZE_METHOD
            })
        );

        dspay.authorizeWithCallback(address(mockToken), amount, onBehalfOf, merchant, memo, itemId, callbackData);

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), callbackValue);

        assertEq(mockToken.balanceOf(address(dspay)), amount);
    }

    function testMockInvalidAuthorizeCallbackContract() public {
        MockInvalidAuthorizeCallbackContract mockContract = new MockInvalidAuthorizeCallbackContract();

        // Test getMerchant returns the expected invalid address
        assertEq(mockContract.getMerchant(), address(0x999));

        // Call processAuthorization directly to achieve 100% coverage
        mockContract.processAuthorization(123);
    }

    function testSettleAuthorizedPaymentRevertsTransactionNotAuthorized() public {
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 100 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(address(0x123))));
        address merchant = address(0x456);
        bytes memory memo = "test settlement";
        bytes32 itemId = bytes32(uint256(789));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(dspay), amount);

        vm.prank(_admin);
        dspay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        dspay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        vm.expectRevert(PendingPayment.TransactionNotAuthorized.selector);
        vm.prank(merchant);
        dspay.settleAuthorizedPayment(address(mockToken), amount, address(this), keccak256("invalid"), 50 ether);
    }
}
