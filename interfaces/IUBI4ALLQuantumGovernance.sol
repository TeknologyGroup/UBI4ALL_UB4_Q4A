// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLQuantumGovernance {
    function proposalCount() external view returns (uint256);
    function createProposal(string memory description) external;
    function executeProposal(uint256 proposalId) external;
    function proposals(uint256 proposalId) external view returns (uint256 id, string memory description, bool isExecuted);
    event ProposalCreated(uint256 indexed proposalId, string description);
    event ProposalExecuted(uint256 indexed proposalId);
}