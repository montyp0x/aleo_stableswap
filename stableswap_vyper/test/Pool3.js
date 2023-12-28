const { expect } = require("chai");
const hre = require("hardhat");
const {
  loadFixture,
  time,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");



describe("StableSwap3Pool", function () {
  async function deployFixture() {
    const [owner, user] = await hre.ethers.getSigners();

    const Pool = await hre.ethers.getContractFactory("StableSwap3Pool");
    const Token = await hre.ethers.getContractFactory("ERC20");

    const lpToken = await Token.deploy("LPTOKEN", "LPT", 18);
    const tokenA = await Token.deploy("TKA", "TKA", 18);
    const tokenB = await Token.deploy("TKB", "TKB", 18);
    const tokenC = await Token.deploy("TKC", "TKC", 18);
    
    lpToken.waitForDeployment();
    tokenA.waitForDeployment();
    tokenB.waitForDeployment();
    tokenC.waitForDeployment();

    const tokenA_addr = await tokenA.getAddress();
    const tokenB_addr = await tokenB.getAddress();
    const tokenC_addr = await tokenC.getAddress();
    const tokenLP_addr = await lpToken.getAddress();
    
    await tokenA.mint(user.address, 1000000);
    await tokenB.mint(user.address, 1000000);
    await tokenC.mint(user.address, 1000000);
    await tokenA.mint(owner.address, 1001000);
    await tokenB.mint(owner.address, 1001000);
    await tokenC.mint(owner.address, 1001000);

    

    const pool = await Pool.deploy(owner.address, [tokenA_addr, tokenB_addr, tokenC_addr], tokenLP_addr, 100, 1, 1);
    
    pool.waitForDeployment();

    const poolAddress = await pool.getAddress();

    await tokenA.connect(user).approve(poolAddress, 1000000);
    await tokenB.connect(user).approve(poolAddress, 1000000);
    await tokenC.connect(user).approve(poolAddress, 1000000);
    await tokenA.connect(owner).approve(poolAddress, 1000000);
    await tokenB.connect(owner).approve(poolAddress, 1000000);
    await tokenC.connect(owner).approve(poolAddress, 1000000);

    await pool.connect(owner).add_liquidity([1000, 2000, 3000], 0);

    return { pool, tokenA, tokenB, tokenC, owner, user };
  }

  it("Mint check", async function () {
    const { tokenA, user } = await loadFixture(deployFixture);

    // assert that the value is correct
    expect(await tokenA.balanceOf(user.address)).to.equal(1000000n);
  });

  it("Exchange", async function () {
    const { pool, tokenA, tokenB, owner, user } = await loadFixture(deployFixture);

    expect(await tokenA.balanceOf(user.address)).to.equal(1000000n);
    expect(await tokenB.balanceOf(user.address)).to.equal(1000000n);

    let A = await pool.connect(owner).A();

    expect(A).to.equal(100n);
    await pool.connect(user).exchange(0, 1, 100, 90);
    
    console.log(await tokenA.balanceOf(user.address));
    console.log(await tokenB.balanceOf(user.address));

    // assert that the value is correct
    expect(await tokenA.balanceOf(user.address)).to.equal(999900n);
    expect(await tokenB.balanceOf(user.address)).to.equal(1000099n);

    await pool.connect(user).exchange(0, 1, 900, 90);
    expect(await tokenA.balanceOf(user.address)).to.equal(999000n);
    expect(await tokenB.balanceOf(user.address)).to.equal(1000933n);
  });

  it("Add/remove liquidity", async function () {
    const { pool, tokenA, tokenB, owner, user } = await loadFixture(deployFixture);

    await pool.connect(owner).add_liquidity([100, 10000, 0], 1);

    await pool.connect(user).exchange(0, 1, 1000, 90);
    console.log(await tokenA.balanceOf(user.address));
    console.log(await tokenB.balanceOf(user.address));

    

  });


});