// SPDX-License-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IUBI4ALLQuantum.sol";
import "../interfaces/IUBI4ALLCustomOracle.sol";
import "../interfaces/IUBI4ALLQuantumGovernance.sol";

contract UBI4ALLQuantumGovernance is IUBI4ALLQuantumGovernance, Ownable {
    IUBI4ALLQuantum public quantumToken;
    IUBI4ALLCustomOracle public customOracle;

    uint256 public constant MINIMUM_TOKENS_FOR_PROPOSAL = 1_000_000 * 10**18; // 1M Q4A
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_PERCENTAGE = 10; // 10% dei token bloccati
    uint256 public constant MAX_INFLUENCE_BONUS = 20; // 20% bonus individuale
    uint256 public constant MAX_ENTANGLEMENT_BONUS = 30; // 30% bonus entanglement
    uint256 public constant ACTIVE_VOTER_THRESHOLD = 5; // 5 proposte in 30 giorni

    struct VoterProfile {
        uint256 totalLocked;
        uint256 proposalCount;
        uint256 lastParticipation;
        uint256 influenceBonus;
    }

    struct EntanglementGroup {
        address[] voters;
        uint256 correlationScore;
    }

    struct Proposal {
        uint256 id;
        string description;
        bool isExecuted;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        mapping(address => bool) hasVoted;
        mapping(address => EntanglementGroup) entanglementGroups;
    }

    mapping(uint256 => Proposal) public _proposals;
    mapping(address => VoterProfile) public voterProfiles;
    uint256 public override proposalCount;

    event VoteCast(address indexed voter, uint256 indexed proposalId, uint8 support, uint256 weight);
    event ReputationUpdated(address indexed voter, uint256 influenceBonus);
    event EntanglementBonusApplied(uint256 indexed proposalId, address indexed voter, uint256 bonusWeight);

    constructor(
        address _quantumToken,
        address _customOracle,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_quantumToken != address(0), "Invalid token address");
        require(_customOracle != address(0), "Invalid oracle address");
        quantumToken = IUBI4ALLQuantum(_quantumToken);
        customOracle = IUBI4ALLCustomOracle(_customOracle);
    }

    function createProposal(string memory description) external override {
        require(quantumToken.balanceOf(msg.sender) >= MINIMUM_TOKENS_FOR_PROPOSAL, "Insufficient Q4A balance");
        proposalCount++;
        Proposal storage newProposal = _proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.description = description;
        newProposal.isExecuted = false;
        newProposal.startTime = block.timestamp;
        newProposal.endTime = block.timestamp + VOTING_PERIOD;
        emit ProposalCreated(proposalCount, description);
    }

    function voteOnProposal(uint256 proposalId, bool support) external {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");
        Proposal storage proposal = _proposals[proposalId];
        require(block.timestamp >= proposal.startTime && block.timestamp <= proposal.endTime, "Voting period closed");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        VoterProfile storage profile = voterProfiles[msg.sender];
        uint256 baseWeight = quantumToken.lockedForDAO(msg.sender);
        require(baseWeight > 0, "No locked Q4A");
        updateVoterProfile(msg.sender);
        uint256 totalWeight = baseWeight + (baseWeight * profile.influenceBonus) / 100;
        uint256 entanglementBonus = calculateEntanglementBonus(proposalId, msg.sender, support);
        totalWeight += entanglementBonus;
        proposal.hasVoted[msg.sender] = true;
        if (support) {
            proposal.forVotes += totalWeight;
        } else {
            proposal.againstVotes += totalWeight;
        }
        emit VoteCast(msg.sender, proposalId, support ? 1 : 0, totalWeight);
        if (entanglementBonus > 0) {
            emit EntanglementBonusApplied(proposalId, msg.sender, entanglementBonus);
        }
    }

    function updateVoterProfile(address voter) internal {
        VoterProfile storage profile = voterProfiles[voter];
        profile.totalLocked = quantumToken.lockedForDAO(voter);
        profile.proposalCount++;
        profile.lastParticipation = block.timestamp;
        uint256 reputationScore = customOracle.getReputationScore(voter);
        if (profile.proposalCount >= ACTIVE_VOTER_THRESHOLD && block.timestamp - profile.lastParticipation < 30 days) {
            profile.influenceBonus = reputationScore > MAX_INFLUENCE_BONUS ? MAX_INFLUENCE_BONUS : reputationScore;
        } else {
            profile.influenceBonus = reputationScore / 2;
        }
        emit ReputationUpdated(voter, profile.influenceBonus);
    }

    function calculateEntanglementBonus(uint256 proposalId, address voter, bool support) internal returns (uint256) {
        Proposal storage proposal = _proposals[proposalId];
        EntanglementGroup storage group = proposal.entanglementGroups[voter];
        if (group.voters.length == 0) {
            group.voters.push(voter);
        }
        uint256 correlationScore = customOracle.getCorrelationScore(voter, proposalId);
        if (support && correlationScore > 0) {
            group.correlationScore = correlationScore > 100 ? 100 : correlationScore;
            uint256 baseWeight = quantumToken.lockedForDAO(voter);
            uint256 bonus = (baseWeight * group.correlationScore * MAX_ENTANGLEMENT_BONUS) / (100 * 100);
            return bonus;
        }
        return 0;
    }

    function executeProposal(uint256 proposalId) external override onlyOwner {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");
        Proposal storage proposal = _proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting period not ended");
        require(!proposal.isExecuted, "Proposal already executed");
        uint256 quorum = (quantumToken.totalLockedForDAO() * QUORUM_PERCENTAGE) / 100;
        require(proposal.forVotes + proposal.againstVotes >= quorum, "Quorum not reached");
        require(proposal.forVotes > proposal.againstVotes, "Proposal not approved");
        proposal.isExecuted = true;
        emit ProposalExecuted(proposalId);
    }

    function updateOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid oracle address");
        customOracle = IUBI4ALLCustomOracle(_newOracle);
    }

    function proposals(uint256 proposalId) external view override returns (uint256 id, string memory description, bool isExecuted) {
        Proposal storage proposal = _proposals[proposalId];
        return (proposal.id, proposal.description, proposal.isExecuted);
    }
}