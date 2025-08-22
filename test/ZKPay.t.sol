// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {ZKPay} from "../src/ZKPay.sol";
import {ZKPayV2} from "./mocks/ZKPayV2.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {AssetManagement} from "../src/libraries/AssetManagement.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ZERO_ADDRESS} from "../src/libraries/Constants.sol";
import {DummyData} from "./data/DummyData.sol";
import {SwapLogic} from "../src/libraries/SwapLogic.sol";
import {PayWallLogic} from "../src/libraries/PayWallLogic.sol";
import {EscrowPayment} from "../src/libraries/EscrowPayment.sol";
import {IZKPay} from "../src/interfaces/IZKPay.sol";

contract MockAuthorizeCallbackContract {
    address private _merchant;
    uint256 public callCount;
    bytes public lastCallData;
    bool public shouldFail;

    error AuthorizeCallbackFailed();

    constructor(address merchant_) {
        _merchant = merchant_;
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

contract MockInvalidAuthorizeCallbackContract {
    // solhint-disable-next-line no-empty-blocks
    function processAuthorization(uint256 value) external pure {}
}

contract ZKPayTest is Test {
    ZKPay public zkpay;
    address public _owner;
    address public _priceFeed;
    AssetManagement.PaymentAsset public paymentAssetInstance;
    address public _sxt;
    int256 public _tokenPrice;

    function setUp() public {
        _owner = vm.addr(0x1);
        _tokenPrice = 1000;

        _priceFeed = address(new MockV3Aggregator(8, _tokenPrice));
        _sxt = address(new MockERC20());
        vm.prank(_owner);
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol", _owner, abi.encodeCall(ZKPay.initialize, (_owner, DummyData.getSwapLogicConfig()))
        );

        zkpay = ZKPay(zkPayProxyAddress);

        paymentAssetInstance =
            AssetManagement.PaymentAsset({priceFeed: _priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 1000});
    }

    function testOwnershipTransfer() public {
        vm.prank(_owner);
        zkpay.transferOwnership(address(0x4));

        assertEq(zkpay.owner(), address(0x4));
    }

    function testOnlyOwnerCanTransferOwnership() public {
        vm.prank(address(0x5));
        vm.expectRevert();
        zkpay.transferOwnership(address(0x6));
    }

    function testTransparentUpgrade() public {
        address proxy = Upgrades.deployTransparentProxy(
            "ZKPay.sol", msg.sender, abi.encodeCall(ZKPay.initialize, (msg.sender, DummyData.getSwapLogicConfig()))
        );
        address implAddressV1 = Upgrades.getImplementationAddress(proxy);
        address adminAddress = Upgrades.getAdminAddress(proxy);

        assertFalse(adminAddress == ZERO_ADDRESS);

        Upgrades.upgradeProxy(proxy, "ZKPayV2.sol", abi.encodeCall(ZKPayV2.initialize, (msg.sender)), msg.sender);
        address implAddressV2 = Upgrades.getImplementationAddress(proxy);

        assertEq(Upgrades.getAdminAddress(proxy), adminAddress);

        assertFalse(implAddressV2 == implAddressV1);

        assertEq(ZKPayV2(implAddressV2).getVersion(), 2);
    }

    function testFuzzSetPaymentAsset(address asset, uint8 tokenDecimals, uint64 stalePriceThresholdInSeconds) public {
        vm.prank(_owner);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(asset, _priceFeed, tokenDecimals, stalePriceThresholdInSeconds);

        zkpay.setPaymentAsset(
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
        vm.prank(_owner);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetAdded(asset, _priceFeed, 18, 1000);

        zkpay.setPaymentAsset(asset, paymentAssetInstance, DummyData.getOriginAssetPath(asset));
    }

    function testFuzzSetPaymentAssetInvalidPath(address asset) public {
        vm.prank(_owner);
        vm.assume(asset != DummyData.getUsdtAddress());

        vm.expectRevert(SwapLogic.InvalidPath.selector);
        zkpay.setPaymentAsset(asset, paymentAssetInstance, DummyData.getDestinationAssetPath(asset));
    }

    function testFuzzOnlyOwnerCanSetPaymentAsset(address caller) public {
        vm.prank(caller);

        if (caller != _owner) {
            vm.expectRevert();
        }

        zkpay.setPaymentAsset(address(0x4), paymentAssetInstance, DummyData.getOriginAssetPath(address(0x4)));
    }

    function testRemovePaymentAsset() public {
        vm.startPrank(_owner);

        vm.expectEmit(true, true, true, true);
        emit AssetManagement.AssetRemoved(address(0x100));

        zkpay.removePaymentAsset(address(0x100));

        vm.expectRevert(AssetManagement.AssetNotFound.selector);
        zkpay.getPaymentAsset(address(0x100));
    }

    function testFuzzOnlyOwnerCanRemovePaymentAsset(address caller) public {
        vm.prank(caller);

        if (caller != _owner) {
            vm.expectRevert();
        }

        zkpay.removePaymentAsset(address(0x100));
    }

    function _setupMockTokenForAuthorize(uint248 amount) internal returns (MockERC20) {
        MockERC20 mockToken = new MockERC20();
        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
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
        zkpay.setPaywallItemPrice(item, price);
        assertEq(zkpay.getPaywallItemPrice(item, merchant), price);
    }

    function testGetExecutorAddress() public view {
        address executorAddress = zkpay.getExecutorAddress();
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
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeIncrementsNonce() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount * 4);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 4, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithZeroValues() public {
        uint248 amount = 0;
        bytes32 onBehalfOf = bytes32(0);
        address merchant = ZERO_ADDRESS;
        bytes memory memo = "";
        bytes32 itemId = bytes32(0);

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        vm.expectRevert(ZKPay.ZeroAmountReceived.selector);
        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        amount = 1;
        mockToken = _setupMockTokenForAuthorize(amount);

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithMaxValues() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(type(uint256).max);
        address merchant = address(type(uint160).max);
        bytes memory memo =
            "maximum length memo that could be very long and contains lots of text to test boundary conditions";
        bytes32 itemId = bytes32(type(uint256).max);

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithLongMemo() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo =
            "This is a very long memo that contains a lot of text to test the handling of long memo fields in the transaction structure and to ensure it works correctly with the authorization process and that the gas costs are reasonable";
        bytes32 itemId = bytes32("longmemo");

        MockERC20 mockToken = _setupMockTokenForAuthorize(amount);

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeMultipleDifferentTransactions() public {
        MockERC20 mockToken = _setupMockTokenForAuthorize(300);

        EscrowPayment.Transaction memory transaction1 = EscrowPayment.Transaction({
            asset: address(mockToken),
            amount: 100,
            from: address(this),
            to: address(0x3333)
        });

        EscrowPayment.Transaction memory transaction2 = EscrowPayment.Transaction({
            asset: address(mockToken),
            amount: 200,
            from: address(this),
            to: address(0x6666)
        });

        bytes32 expectedHash1 = keccak256(abi.encode(transaction1, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(
            transaction1, expectedHash1, bytes32(uint256(uint160(address(0x2222)))), "tx1", bytes32("item1")
        );
        zkpay.authorize(
            transaction1.asset,
            transaction1.amount,
            bytes32(uint256(uint160(address(0x2222)))),
            transaction1.to,
            "tx1",
            bytes32("item1")
        );

        bytes32 expectedHash2 = keccak256(abi.encode(transaction2, 2, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(
            transaction2, expectedHash2, bytes32(uint256(uint160(address(0x5555)))), "tx2", bytes32("item2")
        );
        zkpay.authorize(
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

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 hash1 = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, hash1, onBehalfOf, memo, itemId);
        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        vm.chainId(999);

        EscrowPayment.Transaction memory expectedTransaction2 =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 hash2 = keccak256(abi.encode(expectedTransaction2, 2, 999));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction2, hash2, onBehalfOf, memo, itemId);
        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

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

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
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

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, itemId);

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithUnsupportedAsset() public {
        uint248 amount = 1000;
        bytes32 onBehalfOf = bytes32(uint256(0x5678));
        address merchant = address(0x9abc);
        bytes memory memo = "test payment";
        bytes32 itemId = bytes32("item123");

        MockERC20 mockToken = new MockERC20();
        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.expectRevert(AssetManagement.AssetIsNotSupportedForThisMethod.selector);
        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
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
        zkpay.setPaywallItemPrice(itemId, itemPrice);

        vm.expectRevert(ZKPay.InsufficientPayment.selector);
        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
    }

    function testAuthorizeWithCallbackBasic() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 1000 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "test memo";

        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, 42);

        bytes4 selector = bytes4(callbackData);
        bytes32 expectedItemId = keccak256(abi.encode(address(callbackContract), selector));

        EscrowPayment.Transaction memory expectedTransaction =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 expectedTransactionHash = keccak256(abi.encode(expectedTransaction, 1, block.chainid));

        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction, expectedTransactionHash, onBehalfOf, memo, expectedItemId);

        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 42);

        assertEq(mockToken.balanceOf(address(zkpay)), amount);
        assertEq(mockToken.balanceOf(address(this)), 0);
    }

    function testAuthorizeWithCallbackItemIdGeneration() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "itemId test";

        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, 999);

        bytes4 selector = bytes4(callbackData);
        bytes32 expectedItemId = keccak256(abi.encode(address(callbackContract), selector));
        assertTrue(expectedItemId != bytes32(0));

        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), 999);
    }

    function testAuthorizeWithCallbackInvalidMerchant() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "invalid merchant test";

        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockInvalidAuthorizeCallbackContract invalidCallbackContract = new MockInvalidAuthorizeCallbackContract();
        bytes memory callbackData =
            abi.encodeWithSelector(MockInvalidAuthorizeCallbackContract.processAuthorization.selector, 42);

        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(invalidCallbackContract), callbackData
        );

        assertEq(mockToken.balanceOf(address(zkpay)), amount);
        assertEq(mockToken.balanceOf(address(this)), 0);
    }

    function testAuthorizeWithCallbackFailure() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "callback failure test";

        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        callbackContract.setShouldFail(true);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, 42);

        vm.expectRevert();
        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );

        assertEq(mockToken.balanceOf(address(zkpay)), 0);
        assertEq(mockToken.balanceOf(address(this)), amount);
    }

    function testAuthorizeWithCallbackUnsupportedAsset() public {
        address merchant = vm.addr(0x10);
        address unsupportedToken = vm.addr(0x20);
        uint248 amount = 500 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "unsupported asset test";

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, 42);

        vm.expectRevert();
        zkpay.authorizeWithCallback(
            unsupportedToken, amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );
    }

    function testAuthorizeWithCallbackZeroAmount() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 0;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "zero amount test";

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, 42);

        vm.expectRevert();
        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );
    }

    function testAuthorizeWithCallbackWithPaywallItemPrice() public {
        address merchant = vm.addr(0x10);
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 1000 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(vm.addr(0x11))));
        bytes memory memo = "paywall test";

        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, 789);

        bytes4 selector = bytes4(callbackData);
        bytes32 itemId = keccak256(abi.encode(address(callbackContract), selector));
        uint248 itemPrice = 1;

        vm.prank(merchant);
        zkpay.setPaywallItemPrice(itemId, itemPrice);

        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );

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
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, 123);

        bytes4 selector = bytes4(callbackData);
        bytes32 itemId = keccak256(abi.encode(address(callbackContract), selector));
        uint248 itemPrice = 1000 * 1e18;

        vm.prank(merchant);
        zkpay.setPaywallItemPrice(itemId, itemPrice);

        vm.expectRevert(ZKPay.InsufficientPayment.selector);
        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );
    }

    function testFuzzAuthorizeWithCallback(uint248 amount, uint256 callbackValue, address merchant, bytes32 onBehalfOf)
        public
    {
        amount = uint248(bound(amount, 1, 1000000 ether));
        callbackValue = bound(callbackValue, 0, type(uint256).max);
        vm.assume(merchant != address(0));
        vm.assume(merchant != address(zkpay));

        MockERC20 mockToken = new MockERC20();
        bytes memory memo = "fuzz test";

        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        MockAuthorizeCallbackContract callbackContract = new MockAuthorizeCallbackContract(merchant);
        bytes memory callbackData =
            abi.encodeWithSelector(MockAuthorizeCallbackContract.processAuthorization.selector, callbackValue);

        zkpay.authorizeWithCallback(
            address(mockToken), amount, onBehalfOf, merchant, memo, address(callbackContract), callbackData
        );

        assertEq(callbackContract.callCount(), 1);
        assertEq(abi.decode(callbackContract.lastCallData(), (uint256)), callbackValue);

        assertEq(mockToken.balanceOf(address(zkpay)), amount);
    }

    function testSettleAuthorizedPaymentRevertsTransactionNotAuthorized() public {
        MockERC20 mockToken = new MockERC20();
        uint248 amount = 100 ether;
        bytes32 onBehalfOf = bytes32(uint256(uint160(address(0x123))));
        address merchant = address(0x456);
        bytes memory memo = "test settlement";
        bytes32 itemId = bytes32(uint256(789));

        mockToken.mint(address(this), amount);
        mockToken.approve(address(zkpay), amount);

        vm.prank(_owner);
        zkpay.setPaymentAsset(
            address(mockToken), paymentAssetInstance, DummyData.getOriginAssetPath(address(mockToken))
        );

        zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);

        vm.expectRevert(EscrowPayment.TransactionNotAuthorized.selector);
        zkpay.settleAuthorizedPayment(
            address(mockToken), amount, address(this), merchant, keccak256("invalid"), 50 ether
        );
    }
}
