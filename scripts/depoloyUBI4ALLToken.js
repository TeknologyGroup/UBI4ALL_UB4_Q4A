async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const UBI4ALLToken = await ethers.getContractFactory("UBI4ALLToken");
  const token = await UBI4ALLToken.deploy(
    "0x<treasury_wallet_address>", // _treasuryWallet
    "0x7a1BaC17C7369A3Ce143C4aBa57b240091b4cEF1", // _vrfCoordinator (Polygon Mainnet)
    "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f", // _keyHash
    <your_subscription_id>, // _subscriptionId
    "<oracle_address>", // _oracle (da UBI4ALLCustomOracle)
    "0xdAD8ba732CAd94D107B67248B5425773546AB858" // initialOwner
  );

  await token.deployed();
  console.log("UBI4ALLToken deployed to:", token.address);
}

main().catch(console.error);