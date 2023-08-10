// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IWitnetPriceRouter {
	function valueFor(bytes32 _erc2362id)
        external view
        returns (
            int256 _lastPrice,
            uint256 _lastTimestamp,
            uint256 _latestUpdateStatus
        );
}
