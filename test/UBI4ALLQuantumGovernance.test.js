const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("UBI4ALLQuantumGovernance", function () {
  let quantumGovernance, quantumToken, customOracle, owner, user1, user2;
  const MINIMUM_TOKENS = ethers.parseEther("1000000");
  const VOTING_PERIOD = 7 * 24 * 60 * 60; // 7 giorni in secondi

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const UBI4ALLCustomOracle = await ethers.getContractFactory("UBI4ALLCustomOracle");
    customOracle = await UBI4ALLCustomOracle.deploy(owner.address);
    await customOracle.deployed();

    const UBI4ALLQuantum = await ethers.getContractFactory("UBI4ALLQuantum");
    quantumToken = await UBI4ALLQuantum.deploy(
      owner.address,
      owner.address,
      owner.address,
      owner.address,
      owner.address,
      owner.address
    );
    await quantumToken.deployed();

    const UBI4ALLQuantumGovernance = await ethers.getContractFactory("UBI4ALLQuantumGovernance");
    quantumGovernance = await UBI4ALLQuantumGovernance.deploy(
      quantumToken.address,
      customOracle.address,
      owner.address
    );
    await quantumGovernance.deployed();

    await quantumToken.transfer(user1.address, ethers.parseEther("2000000"));
    await quantumToken.transfer(user2.address, ethers.parseEther("2000000"));
    await quantumToken.connect(user1).lockForDAO(ethers.parseEther("1000000"));
    await quantumToken.connect(user2).lockForDAO(ethers.parseEther("1000000"));
    await customOracle.updateReputationScore(user1.address, 20); // 20% bonus
    await customOracle.updateReputationScore(user2.address, 10); // 10% bonus
  });

  it("should create a proposal", async function () {
    await quantumGovernance.connect(user1).createProposal("Test Proposal");
    const proposal = await quantumGovernance.proposals(1);
    expect(proposal.id).to.equal(1);
    expect(proposal.description).to.equal("Test Proposal");
    expect(proposal.isExecuted).to.equal(false);
  });

  it("should fail to create proposal with insufficient Q4A", async function () {
    await quantumToken.connect(user1).transfer(owner.address, ethers.parseEther("1500000")); // Riduce saldo
    await expect(
      quantumGovernance.connect(user1).createProposal("Invalid Proposal")
    ).to.be.revertedWith("Insufficient Q4A balance");
  });

  it("should vote with influence bonus", async function () {
    await quantumGovernance.connect(user1).createProposal("Test Proposal");
    await quantumGovernance.connect(user1).voteOnProposal(1, true);
    const proposal = await quantumGovernance.proposals(1);
    const expectedWeight = ethers.parseEther("1000000").mul(120).div(100); // 1M Q4A + 20% bonus
    expect(proposal.forVotes).to.equal(expectedWeight);
  });

  it("should update voter profile with reputation", async function () {
    await quantumGovernance.connect(user1).createProposal("Test Proposal");
    await quantumGovernance.connect(user1).voteOnProposal(1, true);
    const profile = await quantumGovernance.voterProfiles(user1.address);
    expect(profile.proposalCount).to.equal(1);
    expect(profile.influenceBonus).to.equal(20); // Bonus pieno per reputazione
    expect(profile.totalLocked).to.equal(ethers.parseEther("1000000"));
  });

  it("should reduce influence bonus for inactive voters", async function () {
    await customOracle.updateReputationScore(user1.address, 20);
    await quantumGovernance.connect(user1).createProposal("Test Proposal");
    await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]); // 31 giorni
    await ethers.provider.send("evm_mine", []);
    await quantumGovernance.connect(user1).voteOnProposal(1, true);
    const profile = await quantumGovernance.voterProfiles(user1.address);
    expect(profile.influenceBonus).to.equal(10); // 20 / 2 per inattività
  });

  it("should execute proposal with quorum", async function () {
    await quantumGovernance.connect(user1).createProposal("Test Proposal");
    await quantumGovernance.connect(user1).voteOnProposal(1, true);
    await quantumGovernance.connect(user2).voteOnProposal(1, true);
    await ethers.provider.send("evm_increaseTime", [VOTING_PERIOD + 1]);
    await ethers.provider.send("evm_mine", []);
    await quantumGovernance.executeProposal(1);
    const proposal = await quantumGovernance.proposals(1);
    expect(proposal.isExecuted).to.equal(true);
  });

  it("should fail to execute proposal without quorum", async function () {
    await quantumGovernance.connect(user1).createProposal("Test Proposal");
    await quantumGovernance.connect(user1).voteOnProposal(1, true);
    await ethers.provider.send("evm_increaseTime", [VOTING_PERIOD + 1]);
    await ethers.provider.send("evm_mine", []);
    await expect(quantumGovernance.executeProposal(1)).to.be.revertedWith("Quorum not reached");
  });

  it("should prevent double voting", async function () {
    await quantumGovernance.connect(user1).createProposal("Test Proposal");
    await quantumGovernance.connect(user1).voteOnProposal(1, true);
    await expect(
      quantumGovernance.connect(user1).voteOnProposal(1, false)
    ).to.be.revertedWith("Already voted");
  });
});