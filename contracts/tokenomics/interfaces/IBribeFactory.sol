// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

interface IBribeFactory {
    function createExternalBribe(address[] memory) external returns (address);
}
