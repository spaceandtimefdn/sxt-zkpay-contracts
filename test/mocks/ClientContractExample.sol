// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IZKPayClient} from "../../src/interfaces/IZKPayClient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ClientContractExample is IZKPayClient, Ownable {
    event CallbackCalled(bytes32 queryHash, bytes queryResult, bytes callbackData);

    error CallFailed();

    constructor(address owner) Ownable(owner) {}

    receive() external payable {}

    function executeCall(address target, bytes calldata data) external payable onlyOwner {
        (bool success,) = target.call{value: msg.value}(data);
        if (!success) revert CallFailed();
    }

    function zkPayCallback(bytes32 queryHash, bytes calldata queryResult, bytes calldata callbackData) external {
        emit CallbackCalled(queryHash, queryResult, callbackData);
    }
}
