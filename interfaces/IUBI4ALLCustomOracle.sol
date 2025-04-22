// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLCustomOracle {
    function getQ4APrice() external view returns (int256);
    function getReputationScore(address voter) external view returns (uint256);
    function getCorrelationScore(address voter, uint256 proposalId) external view returns (uint256);
}