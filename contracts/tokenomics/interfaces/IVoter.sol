// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

interface IVoter {
    function _ve() external view returns (address);
    function governor() external view returns (address);
    function emergencyCouncil() external view returns (address);
    function isWhitelisted(address token) external view returns (bool);
}
