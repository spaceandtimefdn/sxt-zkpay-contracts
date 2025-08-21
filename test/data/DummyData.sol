// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SwapLogic} from "../../src/libraries/SwapLogic.sol";
import {ROUTER, USDT, SXT} from "./MainnetConstants.sol";

library DummyData {
    function getRouterAddress() internal pure returns (address) {
        return ROUTER;
    }

    function getUsdtAddress() internal pure returns (address) {
        return USDT;
    }

    function getOriginAssetPath(address originAsset) internal pure returns (bytes memory) {
        return abi.encodePacked(originAsset, uint24(3000), getUsdtAddress());
    }

    function getDestinationAssetPath(address destinationAsset) internal pure returns (bytes memory) {
        return abi.encodePacked(getUsdtAddress(), uint24(3000), destinationAsset);
    }

    function getSXTAddress() internal pure returns (address) {
        return SXT;
    }

    function getSwapLogicConfig() internal pure returns (SwapLogic.SwapLogicConfig memory) {
        return SwapLogic.SwapLogicConfig({router: getRouterAddress(), usdt: getUsdtAddress()});
    }
}
