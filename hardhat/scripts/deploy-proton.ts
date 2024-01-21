import { ethers } from "hardhat";
const { exec } = require("child_process");

function options() {
  return {/* gasPrice: ethers.utils.parseUnits("700", "gwei") */};
}

function sleep(ms:number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

export default async function oracle() {
  const [account] = await ethers.getSigners()

  //console.log(account);

  console.log("deploying ProtonPack")

  const engineAddress = "0x990c822791d5ac8a24f26821c13333a89f255b4e";
  const ProtonPack = await ethers.getContractFactory("ProtonPack");
  const engine = await ProtonPack.deploy();

  console.log("ProtonPack deployed to:", engine.address);

  const me = "0x0c7d97Caa308E064B9c5e372c8A56201B2eE7BB6"

  const testNetDAI = await ethers.getContractAt(
    "TOKEN",
    "0x29598b72eb5cebd806c5dcd549490fda35b13cd8"
  );

  const testNetAave = await ethers.getContractAt(
    "TOKEN",
    "0x88541670e55cc00beefd87eb59edd1b7c511ac9a"
  );
  const waitBlock = 3;
  console.log("do we have any testnetdai?");
  const balanceeee = await testNetDAI.balanceOf(me);
  console.log(balanceeee.toString())

  const testnetGHO = await ethers.getContractAt(
    "TOKEN",
    "0xc4bf5cbdabe595361438f8c6a187bdc330539c60"
  );

  console.log("approved")
await (  await testNetDAI.approve(engineAddress, "1000000000000000000000000000")).wait(waitBlock);
  console.log("supply")

await (  await engine.supplyToken(0, "10000000000000000000", me, 0)).wait(waitBlock)

  console.log("borrow")
await (  await engine.borrow("3000000000000000000")).wait(waitBlock);
  
  console.log((await engine.loanToValue(me)).toString())
await (  await testnetGHO.approve(engineAddress, "1000000000000000000000000000")).wait(waitBlock);

  console.log("repay")
await (  await engine.repay("1000000000000000000", me)).wait(waitBlock);

  //await sleep(15000);
  console.log("withdraw");

await (  await engine.withdrawToken(0, "1000000000000000000")).wait(waitBlock)

}

oracle();