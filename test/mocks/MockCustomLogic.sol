// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICustomLogic} from "../../src/interfaces/ICustomLogic.sol";
import {QueryLogic} from "../../src/libraries/QueryLogic.sol";

contract MockCustomLogic is ICustomLogic {
    receive() external payable {}

    function getPayoutAddressAndFee() external view override returns (address, uint248) {
        return (address(this), 1e18); // 1 USD
    }

    function execute(QueryLogic.QueryRequest calldata queryRequest, bytes calldata queryResult)
        external
        returns (bytes memory)
    {
        emit Execute(queryRequest, queryResult, address(this));
        return queryResult;
    }
}
