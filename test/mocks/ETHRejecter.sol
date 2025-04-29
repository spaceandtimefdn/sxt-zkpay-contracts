// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ETHRejecter
 * @notice A contract that rejects all ETH transfers to test error handling in withdraw functions
 */
contract ETHRejecter {
    // This contract has no receive or fallback function, so it will reject all ETH transfers

    // This function is just to have something callable on the contract
    function doNothing() external pure returns (bool) {
        return true;
    }
}
