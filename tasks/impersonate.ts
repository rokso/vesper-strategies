import { task } from "hardhat/config";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { parseEther } from "ethers";

task("impersonate", "Impersonate deployment accounts").setAction(async () => {
  if (process.env.DEPLOYER) {
    const deployer = process.env.DEPLOYER;
    await impersonateAccount(deployer);
    await setBalance(deployer, parseEther("1000000"));
  }
});
