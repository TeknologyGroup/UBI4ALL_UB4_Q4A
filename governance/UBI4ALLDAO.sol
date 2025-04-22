// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract UBI4ALLDAO is Ownable {
    IERC20 public ubi4allToken;

    struct Proposal {
        uint256 id;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        uint256 endTime;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(address => mapping(uint256 => bool)) public hasVoted;
    uint256 public proposalCount;
    uint256 public constant VOTING_DURATION = 3 days;

    event ProposalCreated(uint256 proposalId, string description, uint256 endTime);
    event Voted(uint256 proposalId, address voter, bool support);
    event ProposalExecuted(uint256 proposalId);

    constructor(address _ubi4allToken, address initialOwner) Ownable(initialOwner) {
        require(_ubi4allToken != address(0), "Invalid token");
        ubi4allToken = IERC20(_ubi4allToken);
    }

    function createProposal(string memory description) external onlyOwner {
        proposalCount++;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            executed: false,
            endTime: block.timestamp + VOTING_DURATION
        });

        emit ProposalCreated(proposalCount, description, block.timestamp + VOTING_DURATION);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.endTime, "Voting period ended");
        require(!hasVoted[msg.sender][proposalId], "Already voted");
        require(!proposal.executed, "Proposal already executed");

        uint256 votingPower = ubi4allToken.balanceOf(msg.sender);
        require(votingPower > 0, "No voting power");

        if (support) {
            proposal.votesFor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }

        hasVoted[msg.sender][proposalId] = true;
        emit Voted(proposalId, msg.sender, support);
    }

    function executeProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal not passed");

        proposal.executed = true;
        emit ProposalExecuted(proposalId);
    }
}