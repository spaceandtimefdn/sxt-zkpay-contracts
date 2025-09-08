// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract MockSequencerFeedDown {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 1, block.timestamp, block.timestamp, 1);
    }
}

contract MockSequencerFeedGracePeriod {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 0, block.timestamp, block.timestamp, 1);
    }
}
