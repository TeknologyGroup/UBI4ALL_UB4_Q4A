const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("UBI4ALLFinance", function () {
  let token, finance, oracle, owner, user1, user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock oracle
    const MockOracle = await ethers.getContractFactory("MockOracle");
    oracle = await MockOracle.deploy();
    await oracle.setPrice(ethers.parseEther("1.2")); // EUR/USD = 1.2

    // Deploy token
    const UBI4ALLToken = await ethers.getContractFactory("UBI4ALLToken");
    token = await UBI4ALLToken.deploy(
      owner.address,
      "0x7a1BaC17CbcF8fA6cB86eDbA64eA5F5aB7BeF8Ca",
      "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f",
      1234,
      oracle.address
    );

    // Deploy finance
    const UBI4ALLFinance = await ethers.getContractFactory("UBI4ALLFinance");
    finance = await UBI4ALLFinance.deploy(token.address, oracle.address, owner.address);

    // Mint tokens for testing
    await token.transfer(user1.address, ethers.parseEther("10000"));
    await token.transfer(user2.address, ethers.parseEther("10000"));
  });

  it("should allow staking and withdrawing", async function () {
    const stakeAmount = ethers.parseEther("1000");
    await token.connect(user1).approve(finance.address, stakeAmount);
    await finance.connect(user1).stake(stakeAmount);

    expect(await finance.stakedBalance(user1.address)).to.equal(stakeAmount);
    expect(await finance.totalValueLocked()).to.equal(stakeAmount);

    await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]); // 31 days
    await ethers.provider.send("evm_mine");

    await finance.connect(user1).withdraw(stakeAmount);
    expect(await finance.stakedBalance(user1.address)).to.equal(0);
    expect(await finance.totalValueLocked()).to.equal(0);
  });

  it("should apply early withdrawal fee", async function () {
    const stakeAmount = ethers.parseEther("1000");
    await token.connect(user1).approve(finance.address, stakeAmount);
    await finance.connect(user1).stake(stakeAmount);

    const initialBalance = await token.balanceOf(user1.address);
    await finance.connect(user1).withdraw(stakeAmount);

    const finalBalance = await token.balanceOf(user1.address);
    const expectedFee = stakeAmount * 500 / 10000; // 5%
    expect(finalBalance - initialBalance).to.equal(stakeAmount - expectedFee);
  });

  it("should allow requesting and repaying loans", async function () {
    const loanAmount = ethers.parseEther("500");
    const collateral = ethers.parseEther("750");
    await token.connect(user1).approve(finance.address, collateral);
    await finance.connect(user1).requestLoan(loanAmount, 180 * 24 * 60 * 60, collateral);

    expect(await finance.totalLoaned()).to.equal(loanAmount);

    await ethers.provider.send("evm_increaseTime", [90 * 24 * 60 * 60]); // 90 days
    await ethers.provider.send("evm_mine");

    const interest = loanAmount * 200 * 90 / 365 / 10000; // 2% annual
    const totalRepay = loanAmount + interest;
    await token.connect(user1).approve(finance.address, totalRepay);
    await finance.connect(user1).repayLoan(0);

    expect(await finance.totalLoaned()).to.equal(0);
    expect(await token.balanceOf(user1.address)).to.be.closeTo(
      ethers.parseEther("10000") - loanAmount + collateral - interest,
      ethers.parseEther("0.01")
    );
  });
});

// Mock Oracle for testing
const MockOracle = new ethers.ContractFactory(
  [
    "function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80)",
    "function setPrice(uint256 price) external"
  ],
  [
    "function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80) { return (1, int256(price), 0, block.timestamp, 1); }",
    "uint256 price; function setPrice(uint256 _price) external { price = _price; }"
  ],
  ethers
);