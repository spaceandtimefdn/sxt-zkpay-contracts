// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library Utils {
    function isContract(address addr) internal view returns (bool result) {
        assembly {
            result := extcodesize(addr)
        }
    }
}
