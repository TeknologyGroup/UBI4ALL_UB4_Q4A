// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLGovernor {
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string description
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint8 support, uint256 weight);

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256 weight);
    function castVoteWithQuadratic(uint256 proposalId, uint8 support) external returns (uint256 weight);
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable;
    function state(uint256 proposalId) external view returns (uint8);
    function quorum(uint256 blockNumber) external view returns (uint256);
}