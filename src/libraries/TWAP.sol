// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

interface ISwapRouter {
    function factory() external view returns (address);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/// @title TWAP
/// @notice Library for Uniswap V3 Time-Weighted Average Price calculations and slippage validation
/// @dev Provides gas-efficient path parsing using memory pointers and production-ready TWAP calculations
library TWAP {
    /// @notice Thrown when slippage percentage exceeds maximum allowed
    error InvalidSlippage();

    /// @notice Thrown when actual output exceeds slippage tolerance bounds
    error SlippageExceeded();

    /// @notice Thrown when tick value is outside valid range
    error InvalidTick();

    /// @notice Thrown when division by zero occurs in safe math operations
    error DivisionByZero();

    uint256 internal constant ADDRESS_OFFSET_BITS = 96;
    uint256 internal constant FEE_OFFSET_BITS = 232;
    uint256 internal constant WORD_SIZE = 32;
    uint256 internal constant ADDRESS_SIZE = 20;
    uint256 internal constant HOP_SIZE = 23;

    uint32 internal constant TWAP_PERIOD = 3600;
    uint256 internal constant X96_RESOLUTION = 2 ** 96;
    uint256 internal constant TICK_ADJUSTMENT_DIVISOR = 10000;
    uint256 internal constant MIN_PRICE_DIVISOR = 100;
    uint256 internal constant MAX_SLIPPAGE = 100;
    uint256 internal constant FEE_BASIS_POINTS = 1_000_000;

    uint256 private constant INITIAL_RATIO_BASE = 1 << 128;

    /// @notice Gets Uniswap V3 pool address from factory
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param fee Pool fee tier
    /// @param router Uniswap V3 router address
    /// @return pool Pool address from factory
    function getPoolFromFactory(address tokenA, address tokenB, uint24 fee, address router)
        internal
        view
        returns (address pool)
    {
        address factory = ISwapRouter(router).factory();
        pool = IUniswapV3Factory(factory).getPool(tokenA, tokenB, fee);
    }

    /// @notice Parses next hop from Uniswap V3 path using memory pointers
    /// @param path Encoded path bytes
    /// @param ptr Current position pointer in path
    /// @return tokenIn Input token address
    /// @return tokenOut Output token address
    /// @return fee Pool fee for this hop
    /// @return restPtr Pointer to next hop (0 if last hop)
    function getNextPool(bytes memory path, uint256 ptr)
        internal
        pure
        returns (address tokenIn, address tokenOut, uint24 fee, uint256 restPtr)
    {
        assembly {
            let pathPtr := add(path, WORD_SIZE)
            let currentPtr := add(pathPtr, ptr)

            tokenIn := shr(ADDRESS_OFFSET_BITS, mload(currentPtr))
            fee := shr(FEE_OFFSET_BITS, mload(add(currentPtr, ADDRESS_SIZE)))
            tokenOut := shr(ADDRESS_OFFSET_BITS, mload(add(currentPtr, HOP_SIZE)))

            let pathLen := mload(path)
            let remainingLen := sub(pathLen, add(ptr, HOP_SIZE))

            switch gt(remainingLen, ADDRESS_SIZE)
            case 1 { restPtr := add(ptr, HOP_SIZE) }
            default { restPtr := 0 }
        }
    }

    /// @notice Parses path hop and calculates TWAP price from pool observation
    /// @param path Encoded path bytes
    /// @param ptr Current position pointer
    /// @param router Uniswap V3 router address
    /// @return tokenIn Input token address
    /// @return tokenOut Output token address
    /// @return fee Pool fee for this hop
    /// @return restPtr Pointer to next hop (0 if last hop)
    /// @return twapTick 1-hour TWAP tick
    /// @return twapPriceX96 TWAP price in X96 format, adjusted for token ordering
    function getNextPoolWithTwap(bytes memory path, uint256 ptr, address router)
        internal
        view
        returns (address tokenIn, address tokenOut, uint24 fee, uint256 restPtr, int24 twapTick, uint256 twapPriceX96)
    {
        (tokenIn, tokenOut, fee, restPtr) = getNextPool(path, ptr);

        address pool = getPoolFromFactory(tokenIn, tokenOut, fee, router);

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = TWAP_PERIOD;

        int56[] memory tickCumulatives = new int56[](2);
        bool twapSuccess = false;

        // slither-disable-next-line unused-return
        try IUniswapV3Pool(pool).observe(secondsAgos) returns (int56[] memory _tickCumulatives, uint160[] memory) {
            tickCumulatives = _tickCumulatives;
            twapSuccess = true;
        } catch {
            secondsAgos[1] = 0;
            // slither-disable-next-line unused-return
            (tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);
        }

        if (twapSuccess) {
            int56 tickDelta = tickCumulatives[0] - tickCumulatives[1];
            twapTick = int24(tickDelta / int56(int32(uint32(TWAP_PERIOD))));
        } else {
            // slither-disable-next-line unused-return
            (, twapTick,,,,,) = IUniswapV3Pool(pool).slot0();
        }

        uint160 sqrtPriceX96 = _getSqrtRatioAtTick(twapTick);

        uint256 rawPriceX96;
        if (sqrtPriceX96 <= type(uint128).max) {
            rawPriceX96 = (uint256(sqrtPriceX96) * sqrtPriceX96) >> 96;
        } else {
            rawPriceX96 = _mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), X96_RESOLUTION);
        }

        if (tokenIn < tokenOut) {
            twapPriceX96 = rawPriceX96;
        } else {
            twapPriceX96 = _mulDiv(X96_RESOLUTION, X96_RESOLUTION, rawPriceX96);
        }
    }

    /// @notice Validates swap output against TWAP-based slippage tolerance
    /// @param path Multi-hop swap path
    /// @param amountIn Input amount
    /// @param amountOut Actual output amount to validate
    /// @param slippage Slippage tolerance percentage (0-100)
    /// @param router Uniswap V3 router address
    /// @dev Reverts with SlippageExceeded if output is outside tolerance bounds
    function validateSlippageTWAP(
        bytes memory path,
        uint256 amountIn,
        uint256 amountOut,
        uint256 slippage,
        address router
    ) internal view {
        if (slippage > MAX_SLIPPAGE) revert InvalidSlippage();

        uint256 currentAmountIn = amountIn;
        uint256 ptr = 0;

        while (true) {
            (,, uint24 fee, uint256 restPtr,, uint256 twapPriceX96) = getNextPoolWithTwap(path, ptr, router);

            uint256 expectedAmountOut = _calculateAmountOut(currentAmountIn, twapPriceX96, fee);
            currentAmountIn = expectedAmountOut;

            ptr = restPtr;
            if (ptr == 0) break;
        }

        uint256 minAmountOut = (currentAmountIn * (MAX_SLIPPAGE - slippage)) / MAX_SLIPPAGE;
        uint256 maxAmountOut = (currentAmountIn * (MAX_SLIPPAGE + slippage)) / MAX_SLIPPAGE;

        if (amountOut < minAmountOut || amountOut > maxAmountOut) {
            revert SlippageExceeded();
        }
    }

    /// @notice Calculates expected output amount with TWAP price and fees
    /// @param amountIn Input amount
    /// @param twapPriceX96 TWAP price in X96 format
    /// @param fee Pool fee in basis points (e.g., 3000 = 0.3%)
    /// @return Expected output amount after price conversion and fee deduction
    function _calculateAmountOut(uint256 amountIn, uint256 twapPriceX96, uint24 fee) internal pure returns (uint256) {
        uint256 feeMultiplier = FEE_BASIS_POINTS - fee;
        uint256 denominator = X96_RESOLUTION * FEE_BASIS_POINTS;

        return _mulDiv(amountIn * twapPriceX96, feeMultiplier, denominator);
    }

    /// @notice Converts tick to sqrt price using Uniswap V3's official algorithm
    /// @param tick The tick to convert
    /// @return sqrtPriceX96 The sqrt price in X96 format
    /// @dev Uses bit manipulation for gas efficiency, supports full tick range (-887272 to 887272)
    function _getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        if (absTick > uint256(int256(887272))) revert InvalidTick();

        uint256 ratio = _calculateTickRatio(absTick);

        if (tick > 0) {
            ratio = _invertRatio(ratio);
        }

        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /// @notice Calculates the ratio from absolute tick value using Uniswap's algorithm
    /// @param absTick Absolute value of the tick
    /// @return ratio The calculated ratio
    // slither-disable-next-line cyclomatic-complexity
    function _calculateTickRatio(uint256 absTick) private pure returns (uint256 ratio) {
        ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : INITIAL_RATIO_BASE;

        if (absTick & 0x2 != 0) ratio = _applyRatioMultiplier(ratio, 0xfff97272373d413259a46990580e213a);
        if (absTick & 0x4 != 0) ratio = _applyRatioMultiplier(ratio, 0xfff2e50f5f656932ef12357cf3c7fdcc);
        if (absTick & 0x8 != 0) ratio = _applyRatioMultiplier(ratio, 0xffe5caca7e10e4e61c3624eaa0941cd0);
        if (absTick & 0x10 != 0) ratio = _applyRatioMultiplier(ratio, 0xffcb9843d60f6159c9db58835c926644);
        if (absTick & 0x20 != 0) ratio = _applyRatioMultiplier(ratio, 0xff973b41fa98c081472e6896dfb254c0);
        if (absTick & 0x40 != 0) ratio = _applyRatioMultiplier(ratio, 0xff2ea16466c96a3843ec78b326b52861);
        if (absTick & 0x80 != 0) ratio = _applyRatioMultiplier(ratio, 0xfe5dee046a99a2a811c461f1969c3053);
        if (absTick & 0x100 != 0) ratio = _applyRatioMultiplier(ratio, 0xfcbe86c7900a88aedcffc83b479aa3a4);
        if (absTick & 0x200 != 0) ratio = _applyRatioMultiplier(ratio, 0xf987a7253ac413176f2b074cf7815e54);
        if (absTick & 0x400 != 0) ratio = _applyRatioMultiplier(ratio, 0xf3392b0822b70005940c7a398e4b70f3);
        if (absTick & 0x800 != 0) ratio = _applyRatioMultiplier(ratio, 0xe7159475a2c29b7443b29c7fa6e889d9);
        if (absTick & 0x1000 != 0) ratio = _applyRatioMultiplier(ratio, 0xd097f3bdfd2022b8845ad8f792aa5825);
        if (absTick & 0x2000 != 0) ratio = _applyRatioMultiplier(ratio, 0xa9f746462d870fdf8a65dc1f90e061e5);
        if (absTick & 0x4000 != 0) ratio = _applyRatioMultiplier(ratio, 0x70d869a156d2a1b890bb3df62baf32f7);
        if (absTick & 0x8000 != 0) ratio = _applyRatioMultiplier(ratio, 0x31be135f97d08fd981231505542fcfa6);
        if (absTick & 0x10000 != 0) ratio = _applyRatioMultiplier(ratio, 0x9aa508b5b7a84e1c677de54f3e99bc9);
        if (absTick & 0x20000 != 0) ratio = _applyRatioMultiplier(ratio, 0x5d6af8dedb81196699c329225ee604);
        if (absTick & 0x40000 != 0) ratio = _applyRatioMultiplier(ratio, 0x2216e584f5fa1ea926041bedfe98);
        if (absTick & 0x80000 != 0) ratio = _applyRatioMultiplier(ratio, 0x48a170391f7dc42444e8fa2);
    }

    /// @notice Applies ratio multiplier with bit shift
    /// @param ratio Current ratio value
    /// @param multiplier Multiplier constant
    /// @return Updated ratio value
    function _applyRatioMultiplier(uint256 ratio, uint256 multiplier) private pure returns (uint256) {
        return (ratio * multiplier) >> 128;
    }

    /// @notice Inverts the ratio for positive ticks
    /// @param ratio Input ratio to invert
    /// @return Inverted ratio
    function _invertRatio(uint256 ratio) private pure returns (uint256) {
        return type(uint256).max / ratio;
    }

    /// @notice Safe multiplication and division with overflow protection
    /// @param a First multiplicand
    /// @param b Second multiplicand
    /// @param denominator Divisor
    /// @return result Result of (a * b) / denominator without overflow
    /// @dev Uses assembly for gas efficiency and handles overflow cases
    function _mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            if (denominator <= prod1) revert DivisionByZero();

            uint256 remainder;
            assembly {
                remainder := mulmod(a, b, denominator)
            }

            assembly {
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (~denominator + 1);
            uint256 adjustedDenominator;
            uint256 adjustedProd0;

            assembly {
                adjustedDenominator := div(denominator, twos)
                adjustedProd0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            uint256 adjustedNumerator = adjustedProd0 | (prod1 * twos);

            uint256 inverse = _calculateModularInverse(adjustedDenominator);

            result = adjustedNumerator * inverse;
        }
    }

    /// @notice Calculates modular multiplicative inverse using Newton-Raphson method
    /// @param denominator The denominator for which to calculate the inverse
    /// @return inverse The modular multiplicative inverse
    function _calculateModularInverse(uint256 denominator) private pure returns (uint256 inverse) {
        inverse = (3 * denominator) ** 2;

        uint256 temp;

        temp = 2 - denominator * inverse;
        inverse = inverse * temp;

        temp = 2 - denominator * inverse;
        inverse = inverse * temp;

        temp = 2 - denominator * inverse;
        inverse = inverse * temp;

        temp = 2 - denominator * inverse;
        inverse = inverse * temp;

        temp = 2 - denominator * inverse;
        inverse = inverse * temp;

        temp = 2 - denominator * inverse;
        inverse = inverse * temp;
    }
}
