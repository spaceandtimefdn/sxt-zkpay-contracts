// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICustomLogic} from "../../src/interfaces/ICustomLogic.sol";
import {QueryLogic} from "../../src/libraries/QueryLogic.sol";

// this contract is used to test the case where the custom logic contract does not have a receive function
// this is to ensure that the zkpay contract does not revert when the custom logic contract does not have a receive function
contract MockCustomLogicWithoutReceive is ICustomLogic {
    function getMerchantAddressAndFee() external view override returns (address, uint248) {
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
