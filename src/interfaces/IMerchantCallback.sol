// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMerchantCallback {
    function getMerchantAddressAndFee() external view returns (address merchant, uint248 fee);
}
