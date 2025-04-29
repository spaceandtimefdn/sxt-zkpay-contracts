// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IZKPayClient} from "../../src/interfaces/IZKPayClient.sol";

contract FailingClientContract is IZKPayClient {
    error ZkPayCallbackError();

    function zkPayCallback(bytes32, bytes memory, bytes memory) public pure override {
        revert ZkPayCallbackError();
    }
}
