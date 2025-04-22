const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("UBI4ALLGovernor", function () {
  let token, timelock, governor, owner, voter1, voter2;

  beforeEach(async function () {
    [owner, voter1, voter2] = await ethers.getSigners();

    // Deploy token
    const UBI4ALLToken = await ethers.getContractFactory("UBI4ALLToken");
    token = await UBI4ALLToken.deploy(
      owner.address,
      "0x7a1BaC17CbcF8fA6cB86eDbA64eA5F5aB7BeF8Ca",
      "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f",
      1234,
      "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada"
    );

    // Deploy timelock
    const TimelockController = await ethers.getContractFactory("TimelockController");
    timelock = await TimelockController.deploy(172800, [], [], owner.address);

    // Deploy governor
    const UBI4ALLGovernor = await ethers.getContractFactory("UBI4ALLGovernor");
    governor = await UBI4ALLGovernor.deploy(token.address, timelock.address);

    // Set timelock roles
    const proposerRole = await timelock.PROPOSER_ROLE();
    const executorRole = await timelock.EXECUTOR_ROLE();
    await timelock.grantRole(proposerRole, governor.address);
    await timelock.grantRole(executorRole, governor.address);

    // Mint tokens for voters
    await token.transfer(voter1.address, ethers.parseEther("2000000"));
    await token.transfer(voter2.address, ethers.parseEther("2000000"));
  });

  it("should allow proposing and voting", async function () {
    // Create proposal
    const targets = [token.address];
    const values = [0];
    const calldatas = [token.interface.encodeFunctionData("setTreasuryWallet", [voter1.address])];
    const description = "Change treasury wallet";

    await token.connect(voter1).approve(governor.address, ethers.parseEther("1000000"));
    const proposalId = await governor.connect(voter1).propose(targets, values, calldatas, description);
    await ethers.provider.send("evm_mine"); // Wait for voting delay

    // Vote
    await governor.connect(voter1).castVote(proposalId, 1); // Support
    await governor.connect(voter2).castVoteWithQuadratic(proposalId, 1); // Quadratic vote

    // Fast forward to end of voting period
    await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine");

    // Queue and execute
    await governor.queue(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));
    await ethers.provider.send("evm_increaseTime", [2 * 24 * 60 * 60]); // Timelock delay
    await ethers.provider.send("evm_mine");

    await governor.execute(targets, values, calldatas, ethers.keccak256(ethers.toUtf8Bytes(description)));
    expect(await token.treasuryWallet()).to.equal(voter1.address);
  });
});