// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IZKPayClient} from "../../src/interfaces/IZKPayClient.sol";

contract ClientContractExpensiveCallback is IZKPayClient {
    // this gas requires ~12m gas
    function zkPayCallback(bytes32, bytes calldata, bytes calldata) external {
        for (uint256 i = 0; i < 32_777; ++i) {
            keccak256(abi.encode(i));
        }
    }
}
