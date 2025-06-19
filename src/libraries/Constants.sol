// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

address constant NATIVE_ADDRESS = address(0);
address constant ZERO_ADDRESS = address(0);

uint256 constant MAX_GAS_CLIENT_CALLBACK = 3_000_000;

uint256 constant FEE_PRECISION = 1e6;
uint256 constant FEE = 9_000; // 0.9% fee with 6 decimals precision
