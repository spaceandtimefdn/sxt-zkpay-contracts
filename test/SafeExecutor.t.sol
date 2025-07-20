// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SafeExecutor} from "../src/SafeExecutor.sol";
import {ISafeExecutor} from "../src/interfaces/ISafeExecutor.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MockTarget {
    error TargetError();

    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function getValue() external view returns (uint256) {
        return value;
    }

    function revertFunction() external pure {
        revert TargetError();
    }

    function returnData() external pure returns (uint256, string memory) {
        return (42, "test");
    }
}

contract SafeExecutorTest is Test {
    SafeExecutor internal safeExecutor;
    MockTarget internal mockTarget;

    event Executed(address indexed target, bytes result);

    function setUp() public {
        safeExecutor = new SafeExecutor();
        mockTarget = new MockTarget();
    }

    function testExecuteSuccessful() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 123);

        vm.expectEmit(true, false, false, true);
        emit Executed(address(mockTarget), "");

        bytes memory result = safeExecutor.execute(address(mockTarget), data);

        assertEq(result.length, 0);
        assertEq(mockTarget.value(), 123);
    }

    function testExecuteWithReturnData() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.returnData.selector);

        vm.expectEmit(true, false, false, false);
        emit Executed(address(mockTarget), "");

        bytes memory result = safeExecutor.execute(address(mockTarget), data);

        (uint256 num, string memory str) = abi.decode(result, (uint256, string));
        assertEq(num, 42);
        assertEq(str, "test");
    }

    function testExecuteCallFailed() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.revertFunction.selector);

        vm.expectRevert(ISafeExecutor.CallFailed.selector);
        safeExecutor.execute(address(mockTarget), data);
    }

    function testExecuteInvalidTarget() public {
        address nonContractAddress = address(0x123);
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 123);

        vm.expectRevert(ISafeExecutor.InvalidTarget.selector);
        safeExecutor.execute(nonContractAddress, data);
    }

    function testExecuteEOAAddress() public {
        address eoaAddress = address(0x456);
        bytes memory data = "";

        vm.expectRevert(ISafeExecutor.InvalidTarget.selector);
        safeExecutor.execute(eoaAddress, data);
    }

    function testFuzzExecute(uint256 _value) public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, _value);

        vm.expectEmit(true, false, false, true);
        emit Executed(address(mockTarget), "");

        safeExecutor.execute(address(mockTarget), data);

        assertEq(mockTarget.value(), _value);
    }

    function testExecuteWithERC20Mint() public {
        MockERC20 token = new MockERC20();

        bytes memory data = abi.encodeWithSelector(token.mint.selector, address(this), 1000);

        bytes memory result = safeExecutor.execute(address(token), data);

        assertEq(result.length, 0);
        assertEq(token.balanceOf(address(this)), 1000);
    }
}
