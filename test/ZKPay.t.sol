// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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

contract ZKPayTest is Test {
    ZKPay public zkpay;
    address public _owner;
    address public _treasury;
    address public _priceFeed;
    AssetManagement.PaymentAsset public paymentAssetInstance;
    address public _sxt;
    int256 public _tokenPrice;

    function setUp() public {
        _owner = vm.addr(0x1);
        _treasury = vm.addr(0x2);
        _tokenPrice = 1000;

        _priceFeed = address(new MockV3Aggregator(8, _tokenPrice));
        _sxt = address(new MockERC20());
        vm.prank(_owner);
        address zkPayProxyAddress = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            _owner,
            abi.encodeCall(ZKPay.initialize, (_owner, _treasury, _sxt, DummyData.getSwapLogicConfig()))
        );

        zkpay = ZKPay(zkPayProxyAddress);

        paymentAssetInstance =
            AssetManagement.PaymentAsset({priceFeed: _priceFeed, tokenDecimals: 18, stalePriceThresholdInSeconds: 1000});
    }

    function testInitiateTreasuryAddress() public view {
        assertEq(zkpay.getTreasury(), _treasury);
    }

    function testGetSXT() public view {
        assertEq(zkpay.getSXT(), _sxt);
    }

    function testFuzzSetTreasury(address treasury) public {
        vm.prank(_owner);

        if (treasury == ZERO_ADDRESS) {
            vm.expectRevert();
        } else if (treasury == _treasury) {
            vm.expectRevert();
        }

        zkpay.setTreasury(treasury);

        if (treasury != ZERO_ADDRESS && treasury != _treasury) {
            assertEq(zkpay.getTreasury(), treasury);
        }
    }

    function testSetTreasuryCanNotBeZeroAddress() public {
        vm.prank(_owner);
        vm.expectRevert(ZKPay.TreasuryAddressCannotBeZero.selector);
        zkpay.setTreasury(ZERO_ADDRESS);
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

    function testTreasuryAddressCanNotBeSameAsCurrent() public {
        vm.prank(_owner);
        vm.expectRevert(ZKPay.TreasuryAddressSameAsCurrent.selector);
        zkpay.setTreasury(_treasury);
    }

    function testTransparentUpgrade() public {
        address sxt = address(new MockERC20());
        address proxy = Upgrades.deployTransparentProxy(
            "ZKPay.sol",
            msg.sender,
            abi.encodeCall(ZKPay.initialize, (msg.sender, _treasury, sxt, DummyData.getSwapLogicConfig()))
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

    function testOnlyOwnerCanSetTreasury() public {
        vm.prank(address(0x3));
        vm.expectRevert();
        zkpay.setTreasury(address(0x3));
    }

    function testFuzzOnlyOwnerCanSetTreasury(address caller) public {
        vm.prank(caller);

        if (caller != _owner) {
            vm.expectRevert();
        }
        zkpay.setTreasury(caller);
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

    function testInitializeWithZeroSXTAddressReverts() public {
        address implementation = address(new ZKPay());

        bytes memory initData =
            abi.encodeCall(ZKPay.initialize, (_owner, _treasury, ZERO_ADDRESS, DummyData.getSwapLogicConfig()));

        vm.expectRevert(ZKPay.SXTAddressCannotBeZero.selector);
        new TransparentUpgradeableProxy(implementation, _owner, initData);
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
        assertEq(zkpay.getExecutorAddress(), zkpay._executorAddress());
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

        bytes32 transactionHash = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(transactionHash, expectedTransactionHash);
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

        bytes32 transactionHash = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(transactionHash, expectedTransactionHash);
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

        bytes32 transactionHash = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(transactionHash, expectedTransactionHash);
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

        bytes32 transactionHash = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(transactionHash, expectedTransactionHash);
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

        bytes32 transactionHash = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(transactionHash, expectedTransactionHash);
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
        bytes32 hash1 = zkpay.authorize(
            transaction1.asset,
            transaction1.amount,
            bytes32(uint256(uint160(address(0x2222)))),
            transaction1.to,
            "tx1",
            bytes32("item1")
        );
        assertEq(hash1, expectedHash1);

        bytes32 expectedHash2 = keccak256(abi.encode(transaction2, 2, block.chainid));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(
            transaction2, expectedHash2, bytes32(uint256(uint160(address(0x5555)))), "tx2", bytes32("item2")
        );
        bytes32 hash2 = zkpay.authorize(
            transaction2.asset,
            transaction2.amount,
            bytes32(uint256(uint160(address(0x5555)))),
            transaction2.to,
            "tx2",
            bytes32("item2")
        );
        assertEq(hash2, expectedHash2);
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
        bytes32 actualHash1 = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(actualHash1, hash1);

        vm.chainId(999);

        EscrowPayment.Transaction memory expectedTransaction2 =
            EscrowPayment.Transaction({asset: address(mockToken), amount: amount, from: address(this), to: merchant});

        bytes32 hash2 = keccak256(abi.encode(expectedTransaction2, 2, 999));
        vm.expectEmit(true, true, true, true);
        emit IZKPay.Authorized(expectedTransaction2, hash2, onBehalfOf, memo, itemId);
        bytes32 actualHash2 = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(actualHash2, hash2);

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

        bytes32 transactionHash = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(transactionHash, expectedTransactionHash);
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

        bytes32 transactionHash = zkpay.authorize(address(mockToken), amount, onBehalfOf, merchant, memo, itemId);
        assertEq(transactionHash, expectedTransactionHash);
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
}
