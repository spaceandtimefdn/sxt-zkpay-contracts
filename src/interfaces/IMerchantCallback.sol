// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMerchantCallback {
    function getMerchant() external view returns (address merchant);
}
