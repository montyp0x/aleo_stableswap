require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-vyper");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.18",
  },
  vyper: {
    version: "0.3.10", 
  },
};

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

task("test-leo", "t")
  .addParam("amountIn", "in")
  .addParam("reserveIn", "rin")
  .addParam("reserveOut", "rout")
  .setAction(async (taskArgs) => {

    const amount_in = await taskArgs.amountIn;
    const reserve_in = await taskArgs.reserveIn;
    const reserve_out = await taskArgs.reserveOut;
    
    const [owner, user] = await hre.ethers.getSigners();

    const Pool = await hre.ethers.getContractFactory("StableSwap2Pool");
    const Token = await hre.ethers.getContractFactory("ERC20");

    const lpToken = await Token.deploy("LPTOKEN", "LPT", 18);
    const tokenA = await Token.deploy("TKA", "TKA", 18);
    const tokenB = await Token.deploy("TKB", "TKB", 18);
    
    lpToken.waitForDeployment();
    tokenA.waitForDeployment();
    tokenB.waitForDeployment();

    const tokenA_addr = await tokenA.getAddress();
    const tokenB_addr = await tokenB.getAddress();
    const tokenLP_addr = await lpToken.getAddress();
    
    await tokenA.mint(user.address, amount_in);
    // await tokenB.mint(user.address, 1000000);
    await tokenA.mint(owner.address, 1001000000);
    await tokenB.mint(owner.address, 1001000000);

    const pool = await Pool.deploy(owner.address, [tokenA_addr, tokenB_addr], tokenLP_addr, 100, 1, 1);
    
    pool.waitForDeployment();

    const poolAddress = await pool.getAddress();

    await tokenA.connect(user).approve(poolAddress, amount_in);
    // await tokenB.connect(user).approve(poolAddress, 1000000);
    await tokenA.connect(owner).approve(poolAddress, 1000000000);
    await tokenB.connect(owner).approve(poolAddress, 1000000000);

    await pool.connect(owner).add_liquidity([reserve_in, reserve_out], 0);

    await pool.connect(user).exchange(0, 1, amount_in, 1);

    console.log(await tokenB.balanceOf(user.address));
  });