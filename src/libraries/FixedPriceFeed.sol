// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title FixedPriceFeed
 * @notice This is a mock contract for the AggregatorV2V3 to return a fixed price.
 */
contract FixedPriceFeed {
    uint8 public immutable DECIMALS;
    int256 public immutable PRICE;
    uint256 public immutable STARTED_AT;

    constructor(uint8 priceDecimals, int256 price) {
        DECIMALS = priceDecimals;
        PRICE = price;
        STARTED_AT = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (uint80(0), PRICE, STARTED_AT, block.timestamp, uint80(0));
    }

    function decimals() external view returns (uint8) {
        return DECIMALS;
    }

    function latestAnswer() external view returns (int256) {
        return PRICE;
    }
}
