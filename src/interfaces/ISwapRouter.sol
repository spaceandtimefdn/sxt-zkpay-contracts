// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ISwapRouter
/// @dev copied from @uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol
interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
