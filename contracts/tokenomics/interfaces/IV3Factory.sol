// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

interface IV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}
