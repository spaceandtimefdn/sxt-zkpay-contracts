// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICustomLogic} from "./interfaces/ICustomLogic.sol";
import {QueryLogic} from "./libraries/QueryLogic.sol";

contract PoSQLVerifier is ICustomLogic {
    address public immutable MERCHANT_ADDRESS;
    address private immutable OWNER;

    error ZeroAddressNotAllowed();
    error OnlyOwnerAllowed();

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert OnlyOwnerAllowed();
        _;
    }

    constructor(address merchantAddress) {
        if (merchantAddress == address(0)) revert ZeroAddressNotAllowed();
        MERCHANT_ADDRESS = merchantAddress;
        OWNER = msg.sender;
    }

    receive() external payable {}

    /// @notice Returns the payout address and fee
    /// @return merchantAddress The merchant address
    /// @return fee The fee (1 USD)
    function getMerchantAddressAndFee() external view override returns (address merchantAddress, uint248 fee) {
        return (MERCHANT_ADDRESS, 1e18);
    }

    function execute(QueryLogic.QueryRequest calldata queryRequest, bytes calldata queryResult)
        external
        returns (bytes memory)
    {
        emit Execute(queryRequest, queryResult, MERCHANT_ADDRESS);
        return queryResult;
    }

    /// @notice Allows the contract owner to withdraw any ETH that might be sent to this contract
    /// @dev Added to address Slither warning about contracts locking ether
    // slither-disable-next-line low-level-calls
    function withdraw() external onlyOwner {
        payable(OWNER).transfer(address(this).balance);
    }
}
