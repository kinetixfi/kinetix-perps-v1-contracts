// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardTracker.sol";

contract StakedKlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee + Staked KLP", "fsKLP") {}
}

contract FeeKlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee KLP", "fKLP") {}
}
