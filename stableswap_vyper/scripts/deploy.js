const hre = require("hardhat");
const fs = require("fs");
const { ethers } = require("hardhat");

async function main() {
  await hre.run("compile");
  
  const [owner] = await hre.ethers.getSigners();
  // console.log(owner.address);

  const Pool = await hre.ethers.getContractFactory("StableSwap3Pool");
  const Token = await hre.ethers.getContractFactory("ERC20");

  const lpToken = await Token.deploy("LPTOKEN", "LPT", 9, 1000);
  const tokenA = await Token.deploy("TKA", "TKA", 9, 1000);
  const tokenB = await Token.deploy("TKB", "TKB", 9, 1000);
  
  lpToken.waitForDeployment();
  tokenA.waitForDeployment();
  tokenB.waitForDeployment();

  const tokenA_addr = await tokenA.getAddress();
  const tokenB_addr = await tokenB.getAddress();
  const tokenLP_addr = await lpToken.getAddress();
  
  const pool = await Pool.deploy(owner.address, [tokenA_addr, tokenB_addr], tokenLP_addr, 100, 1, 1);
  
  pool.waitForDeployment();

  let details = {
    deployer: owner.address,
    contract: await pool.getAddress()
  };

  console.log(
    `Account: ${details.deployer} deployed Contract: ${details.contract}`
  );

  fs.writeFile("./details.json", JSON.stringify(details, null, 2), (err) => {
    if (err) {
      return console.log(err);
    }
    return console.log("Details are saved!!");
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
