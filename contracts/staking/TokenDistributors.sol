// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardDistributor.sol";


contract StakedKlpDistributor is RewardDistributor {
    constructor(address _rewardTracker) public RewardDistributor(_rewardTracker) {}
}
contract FeeKlpDistributor is RewardDistributor {
    constructor(address _rewardTracker) public RewardDistributor(_rewardTracker) {}
}
