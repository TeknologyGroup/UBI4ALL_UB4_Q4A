const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("UBI4ALLQuantumFinance", function () {
  let quantumFinance, quantumToken, oracle, owner, user1;
  const ORACLE_ADDRESS = "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada";

  beforeEach(async function () {
    [owner, user1, treasury] = await ethers.getSigners();

    const UBI4ALLOracle = await ethers.getContractFactory("UBI4ALLOracle");
    oracle = await UBI4ALLOracle.deploy(ORACLE_ADDRESS, owner.address);
    await oracle.deployed();

    const UBI4ALLQuantum = await ethers.getContractFactory("UBI4ALLQuantum");
    quantumToken = await UBI4ALLQuantum.deploy(
      treasury.address,
      treasury.address,
      treasury.address,
      treasury.address,
      treasury.address,
      owner.address
    );
    await quantumToken.deployed();

    const UBI4ALLQuantumFinance = await ethers.getContractFactory("UBI4ALLQuantumFinance");
    quantumFinance = await UBI4ALLQuantumFinance.deploy(
      quantumToken.address,
      oracle.address,
      owner.address
    );
    await quantumFinance.deployed();

    await quantumToken.transfer(user1.address, ethers.parseEther("10000"));
    await quantumToken.connect(user1).approve(quantumFinance.address, ethers.parseEther("10000"));
  });

  it("should stake Q4A", async function () {
    await quantumFinance.connect(user1).stake(ethers.parseEther("1000"));
    expect(await quantumFinance.getStakedBalance(user1.address)).to.equal(ethers.parseEther("1000"));
    expect(await quantumFinance.getTotalValueLocked()).to.equal(ethers.parseEther("1000"));
  });

  it("should stake Q4A for DAO with higher yield", async function () {
    await quantumFinance.connect(user1).stakeForDAO(ethers.parseEther("1000"));
    expect(await quantumFinance.getStakedBalance(user1.address)).to.equal(ethers.parseEther("1000"));
    await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);
    const reward = await quantumFinance.calculateReward(user1.address);
    expect(reward).to.be.above(ethers.parseEther("120")); // 12% APY
  });

  it("should increase yield with volatility", async function () {
    // Simula variazioni di prezzo
    await quantumFinance.updatePrice();
    await ethers.provider.send("evm_increaseTime", [1 * 24 * 60 * 60]);
    await quantumFinance.updatePrice();
    await quantumFinance.connect(user1).stake(ethers.parseEther("1000"));
    await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);
    const reward = await quantumFinance.calculateReward(user1.address);
    expect(reward).to.be.above(ethers.parseEther("120")); // >10% con volatilità
  });

  it("should withdraw staked Q4A", async function () {
    await quantumFinance.connect(user1).stake(ethers.parseEther("1000"));
    const initialBalance = await quantumToken.balanceOf(user1.address);
    await quantumFinance.connect(user1).withdraw(ethers.parseEther("500"));
    expect(await quantumFinance.getStakedBalance(user1.address)).to.equal(ethers.parseEther("500"));
    expect(await quantumToken.balanceOf(user1.address)).to.equal(initialBalance.add(ethers.parseEther("500")));
  });

  it("should claim rewards", async function () {
    await quantumFinance.connect(user1).stake(ethers.parseEther("1000"));
    await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);
    const initialBalance = await quantumToken.balanceOf(user1.address);
    await quantumFinance.connect(user1).claimReward();
    expect(await quantumToken.balanceOf(user1.address)).to.be.above(initialBalance);
  });
});