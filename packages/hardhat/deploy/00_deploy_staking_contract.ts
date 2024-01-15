import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

/**
 * Deploys a contract named "StakingContract" using the deployer account and
 * constructor arguments set to the deployer address
 *
 * @param hre HardhatRuntimeEnvironment object.
 */
const deployStakingContract: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  /*
    On localhost, the deployer account is the one that comes with Hardhat, which is already funded.

    When deploying to live networks (e.g `yarn deploy --network goerli`), the deployer account
    should have sufficient balance to pay for the gas fees for contract creation.

    You can generate a random account with `yarn generate` which will fill DEPLOYER_PRIVATE_KEY
    with a random private key in the .env file (then used on hardhat.config.ts)
    You can run the `yarn account` command to check your balance in every network.
  */
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
  await sleep(1000);

  await deploy("StakingContract", {
    from: deployer,
    // Contract constructor arguments
    //args: [deployer],
    log: true,
    // autoMine: can be passed to the deploy function to make the deployment process faster on local networks by
    // automatically mining the contract deployment transaction. There is no effect on live networks.
    autoMine: true,
  });

  // Get the deployed contract
  const stakingContract = await hre.ethers.getContract("StakingContract", deployer);

  console.log("\nDeployer address: ",  deployer);

  console.log("\nSmart contract address: ",  stakingContract.address);


  //Deploy W3M token dummy smart contract

  await deploy("W3MToken", {
    from: deployer,
    // Contract constructor arguments
    //args: [deployer],
    log: true,
    // autoMine: can be passed to the deploy function to make the deployment process faster on local networks by
    // automatically mining the contract deployment transaction. There is no effect on live networks.
    autoMine: true,
  });

  // Get the deployed contract
  const w3MToken = await hre.ethers.getContract("W3MToken", deployer);

  //Update W3MTokenAddress
  await stakingContract.updateW3MTokenAddress(w3MToken.address);

  ////////////////Send 10M tokens to investor address
  await w3MToken.transfer(
    "0x350441F8a82680a785FFA9d3EfEa60BB4cA417f8", hre.ethers.utils.parseUnits("10000000", 18)
  );

  var investorAddressBalance = await w3MToken.balanceOf("0x350441F8a82680a785FFA9d3EfEa60BB4cA417f8"); 

  console.log("Balance of investor address is: ", investorAddressBalance.toString());

  //Add investor address to staking contract whitelist
  await stakingContract.addToWhiteList("0x350441F8a82680a785FFA9d3EfEa60BB4cA417f8");

  //Add owner address to staking contract whitelist
  await stakingContract.addToWhiteList("0x498C47066AdeB22Ba23953d890eD6b540411e350");


  ////////////////Send 100M tokens to staking contract address to offer as rewards
  await w3MToken.transfer(
    stakingContract.address, hre.ethers.utils.parseUnits("100000000", 18)
  );

  ////////////////Send 100M to address of the owner so the staking smart contract so he can feed tokens for rewards
  await w3MToken.transfer(
    "0x498C47066AdeB22Ba23953d890eD6b540411e350", hre.ethers.utils.parseUnits("100000000", 18)
  );

  // Transfer ownership of staking smart contract
  await stakingContract.transferOwnership("0x498C47066AdeB22Ba23953d890eD6b540411e350");

};

export default deployStakingContract;

// Tags are useful if you have multiple deploy files and only want to run one of them.
// e.g. yarn deploy --tags StakingContract
deployStakingContract.tags = ["StakingContract", "W3MToken"];
