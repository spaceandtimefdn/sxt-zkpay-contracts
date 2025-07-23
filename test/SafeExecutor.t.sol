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

    function revertFunction() external pure {
        revert TargetError();
    }
}

contract SafeExecutorTest is Test {
    SafeExecutor internal safeExecutor;
    MockTarget internal mockTarget;

    function setUp() public {
        safeExecutor = new SafeExecutor();
        mockTarget = new MockTarget();
    }

    function testExecuteSuccessful() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 123);

        safeExecutor.execute(address(mockTarget), data);

        assertEq(mockTarget.value(), 123);
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

        safeExecutor.execute(address(mockTarget), data);

        assertEq(mockTarget.value(), _value);
    }

    function testExecuteWithERC20Mint() public {
        MockERC20 token = new MockERC20();

        bytes memory data = abi.encodeWithSelector(token.mint.selector, address(this), 1000);

        safeExecutor.execute(address(token), data);

        assertEq(token.balanceOf(address(this)), 1000);
    }
}
