const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("UBI4ALLToken", function () {
  let ubi4allToken, quantumToken, oracle, owner, user1, user2, treasury;
  const TOTAL_SUPPLY = ethers.parseEther("10000000000");
  const LOTTERY_AMOUNT = ethers.parseEther("100000");
  const VRF_COORDINATOR = "0x7a1BaC17CbcF8fA6cB86eDbA64eA5F5aB7BeF8Ca";
  const KEY_HASH = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";
  const SUBSCRIPTION_ID = 1234;
  const ORACLE_ADDRESS = "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada";

  beforeEach(async function () {
    [owner, user1, user2, treasury] = await ethers.getSigners();

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

    const UBI4ALLToken = await ethers.getContractFactory("UBI4ALLToken");
    ubi4allToken = await UBI4ALLToken.deploy(
      treasury.address,
      VRF_COORDINATOR,
      KEY_HASH,
      SUBSCRIPTION_ID,
      oracle.address,
      owner.address
    );
    await ubi4allToken.deployed();

    await ubi4allToken.setQuantumToken(quantumToken.address);
    await quantumToken.transfer(ubi4allToken.address, ethers.parseEther("1000000"));
    await ubi4allToken.transfer(user1.address, ethers.parseEther("1000"));
    await ubi4allToken.transfer(user2.address, ethers.parseEther("1000"));
  });

  it("should start and enter lottery", async function () {
    await ubi4allToken.startLottery();
    await ubi4allToken.connect(user1).enterLottery();
    await ubi4allToken.connect(user2).enterLottery();
    const participants = await ubi4allToken.lotteryParticipants();
    expect(participants.length).to.equal(2);
  });

  it("should distribute UB4 and Q4A rewards", async function () {
    await ubi4allToken.toggleQ4ARewards(true);
    await ubi4allToken.startLottery();
    await ubi4allToken.connect(user1).enterLottery();
    await ubi4allToken.connect(user2).enterLottery();
    await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    // Simula VRF callback
    const winner = user1.address;
    await ubi4allToken.endLottery();
    // Supponiamo che il VRF selezioni user1 (mock manuale)
    await ubi4allToken.fulfillRandomWords(0, [1]); // Mock random word
    expect(await ubi4allToken.balanceOf(user1.address)).to.be.above(ethers.parseEther("50000"));
    expect(await quantumToken.balanceOf(user1.address)).to.be.above(ethers.parseEther("50000"));
  });

  it("should apply lottery and burn fees", async function () {
    const initialBalance = await ubi4allToken.balanceOf(user1.address);
    await ubi4allToken.connect(user1).transfer(user2.address, ethers.parseEther("100"));
    const finalBalance = await ubi4allToken.balanceOf(user1.address);
    const expectedBurn = ethers.parseEther("100").mul(50).div(10000);
    const expectedLotteryFee = ethers.parseEther("100").mul(700).div(10000);
    expect(initialBalance.sub(finalBalance)).to.equal(
      ethers.parseEther("100").add(expectedBurn).add(expectedLotteryFee)
    );
    expect(await ubi4allToken.balanceOf(treasury.address)).to.equal(expectedLotteryFee);
  });

  it("should recover tokens in emergency", async function () {
    await quantumToken.transfer(ubi4allToken.address, ethers.parseEther("1000"));
    await ubi4allToken.emergencyRecoverTokens(quantumToken.address, owner.address, ethers.parseEther("1000"));
    expect(await quantumToken.balanceOf(owner.address)).to.equal(ethers.parseEther("1000"));
  });
});