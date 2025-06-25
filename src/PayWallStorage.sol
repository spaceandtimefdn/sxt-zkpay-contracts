// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery//contracts/interfaces/ISwapRouter.sol";

/// @title PayWallStorage
/// @dev All layout, modifiers & internal helpers live here, separated from logic.
abstract contract PayWallStorage is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct MerchantConfig {
        address payoutAddress; // 0 ⇒ fallback to merchant EOAs
        address targetAsset; // 0 ⇒ defaultTargetAsset (SXT)
        mapping(bytes32 itemId => uint248) minPrice; // 0 ⇒ no floor
    }

    ISwapRouter public immutable swapRouter; // uniswap v3 router
    address public immutable SXT; // canonical SXT token

    address public treasury; // protocol‑fee sink
    mapping(address => bool) public whitelistedSource; // ERC‑20 → whitelisted?
    mapping(address => MerchantConfig) private merchantConfig; // merchant → cfg

    event TreasurySet(address indexed treasury);

    constructor(address _router, address _sxt) {
        require(_router != address(0) && _sxt != address(0), "ZERO_ADDRESS");
        swapRouter = ISwapRouter(_router);
        SXT = _sxt;
    }
}
