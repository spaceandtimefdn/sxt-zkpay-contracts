// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Create a mock contract that will reject receiving ETH
contract RejectEther {
    error EtherRejected();

    fallback() external payable {
        revert EtherRejected();
    }

    receive() external payable {
        revert EtherRejected();
    }
}
