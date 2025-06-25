// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title SwapLogicLib
/// @notice Internal helper for single‑hop swaps through Uniswap V3.
/// @dev Keeps the PayWall contract lean and deterministic.
library SwapLogicLib {
    using SafeERC20 for IERC20;

    /// Default pool fee tier (0.3 % = 3000).
    uint24 internal constant DEFAULT_POOL_FEE = 3_000;

    /**
     * @notice Swap `amountIn` of `tokenIn` to `tokenOut` via Uniswap V3.
     * @param router  Deployed Uniswap V3 router address (immutable in PayWall).
     * @param tokenIn ERC‑20 to sell.
     * @param tokenOut ERC‑20 to buy.
     * @param amountIn Exact amount of `tokenIn` to swap (already held by caller).
     * @param recipient Address that ultimately receives `tokenOut`.
     * @return amountOut Exact `tokenOut` received.
     */
    function swapExactInput(ISwapRouter router, address tokenIn, address tokenOut, uint256 amountIn, address recipient)
        internal
        returns (uint256 amountOut)
    {
        if (tokenIn == tokenOut) {
            // No swap needed; caller will forward funds.
            return amountIn;
        }

        IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: DEFAULT_POOL_FEE,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0, // slippage handled off‑chain / by router‑integrated oracles
            sqrtPriceLimitX96: 0 // no price limit
        });

        amountOut = router.exactInputSingle(params);

        // Reset approval to 0 as a hygiene measure.
        IERC20(tokenIn).safeApprove(address(router), 0);
    }
}
