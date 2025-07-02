// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SwapLogic} from "../../src/libraries/SwapLogic.sol";

library DummyData {
    function getRouterAddress() internal pure returns (address) {
        return 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    }

    function getUsdtAddress() internal pure returns (address) {
        return 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    }

    function getSwapPath() internal pure returns (bytes memory) {
        return abi.encodePacked(getUsdtAddress());
    }

    function getSwapLogicConfig() internal pure returns (SwapLogic.SwapLogicConfig memory) {
        return SwapLogic.SwapLogicConfig({
            router: getRouterAddress(),
            usdt: getUsdtAddress(),
            defaultTargetAssetPath: getSwapPath()
        });
    }
}
