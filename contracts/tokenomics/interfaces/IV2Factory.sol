// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

interface IV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
