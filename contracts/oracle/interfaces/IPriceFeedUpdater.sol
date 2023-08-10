// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IPriceFeedUpdater {
    function setLatestAnswer(int256 _answer) external ;
}
