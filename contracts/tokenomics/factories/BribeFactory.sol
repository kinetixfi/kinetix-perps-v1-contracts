// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "../interfaces/IBribeFactory.sol";
import "../ExternalBribe.sol";

contract BribeFactory is IBribeFactory {
    address public last_external_bribe;

    function createExternalBribe(address[] memory allowedRewards) external returns (address) {
        last_external_bribe = address(new ExternalBribe(msg.sender,allowedRewards));
        return last_external_bribe;
    }
}
