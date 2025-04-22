const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Deploy UBI4ALLToken
  const treasuryWallet = deployer.address;
  const vrfCoordinator = "0x7a1BaC17CbcF8fA6cB86eDbA64eA5F5aB7BeF8Ca";
  const keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";
  const subscriptionId = 1234; // Replace with actual VRF subscription ID
  const priceFeed = "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada";

  const UBI4ALLToken = await hre.ethers.getContractFactory("UBI4ALLToken");
  const token = await UBI4ALLToken.deploy(
    treasuryWallet,
    vrfCoordinator,
    keyHash,
    subscriptionId,
    priceFeed
  );
  await token.waitForDeployment();
  console.log("UBI4ALLToken deployed to:", token.target);

  // Deploy UBI4ALLOracle
  const UBI4ALLOracle = await hre.ethers.getContractFactory("UBI4ALLOracle");
  const oracle = await UBI4ALLOracle.deploy(priceFeed, deployer.address);
  await oracle.waitForDeployment();
  console.log("UBI4ALLOracle deployed to:", oracle.target);

  // Deploy UBI4ALLFinance
  const UBI4ALLFinance = await hre.ethers.getContractFactory("UBI4ALLFinance");
  const finance = await UBI4ALLFinance.deploy(token.target, oracle.target, deployer.address);
  await finance.waitForDeployment();
  console.log("UBI4ALLFinance deployed to:", finance.target);

  // Deploy UBI4ALLTimelock
  const minDelay = 172800; // 2 days
  const proposers = []; // To be set after governor deployment
  const executors = [];
  const TimelockController = await hre.ethers.getContractFactory("TimelockController");
  const timelock = await TimelockController.deploy(minDelay, proposers, executors, deployer.address);
  await timelock.waitForDeployment();
  console.log("UBI4ALLTimelock deployed to:", timelock.target);

  // Deploy UBI4ALLGovernor
  const UBI4ALLGovernor = await hre.ethers.getContractFactory("UBI4ALLGovernor");
  const governor = await UBI4ALLGovernor.deploy(token.target, timelock.target);
  await governor.waitForDeployment();
  console.log("UBI4ALLGovernor deployed to:", governor.target);

  // Set roles in Timelock
  const proposerRole = await timelock.PROPOSER_ROLE();
  const executorRole = await timelock.EXECUTOR_ROLE();
  await timelock.grantRole(proposerRole, governor.target);
  await timelock.grantRole(executorRole, governor.target);
  console.log("Timelock roles assigned");

  // Set governance and finance contracts in token
  await token.setGovernanceContract(governor.target);
  await token.setFinanceContract(finance.target);
  console.log("Governance and finance contracts set in token");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});