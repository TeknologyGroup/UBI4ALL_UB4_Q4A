async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const CustomOracle = await ethers.getContractFactory("UBI4ALLCustomOracle");
  const oracle = await CustomOracle.deploy(
    "0x6E2dc0b449d45954F6272D5B63EFa1FDB1A94f3B", // _functionsRouter
    "0x66756e2d706f6c79676f6e2d6d61696e6e65742d31", // _donID
    <your_subscription_id>, // _subscriptionId
    "0xdAD8ba732CAd94D107B67248B5425773546AB858" // initialOwner
  );

  await oracle.deployed();
  console.log("UBI4ALLCustomOracle deployed to:", oracle.address);
}

main().catch(console.error);