import hre from "hardhat";
import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { saveForSafeBatchExecution } from "./safe";
import { deploy, DeployParams } from "./deploy";
import { IPoolAccountant } from "../typechain-types";
import { Address } from "./address";

type ConfigParams = {
  keeper?: string;
  debtRatio?: string;
  externalDepositFee?: string;
};

export const executeOrStoreTxIfMultisig = async (
  hre: HardhatRuntimeEnvironment,
  executeFunction: () => Promise<unknown>,
): Promise<void> => {
  const { deployments } = hre;
  const { catchUnknownSigner } = deployments;

  const multisigTx = await catchUnknownSigner(executeFunction, { log: true });

  if (multisigTx) {
    console.log(
      chalk.yellow("Note: Current wallet cannot execute transaction. It will be executed by safe later in the flow."),
    );
    await saveForSafeBatchExecution(multisigTx);
  }
};

async function addStrategy(
  hre: HardhatRuntimeEnvironment,
  strategyName: string,
  strategyAddress: string,
  configParams?: ConfigParams,
): Promise<void> {
  const { read } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  // if strategy is not active then add it into pool accountant
  if (!(await read(strategyName, "isActive"))) {
    const paAddress = await read(strategyName, "poolAccountant");
    const poolAccountant = (await hre.ethers.getContractAt("IPoolAccountant", paAddress)) as IPoolAccountant;
    const governor = await read(strategyName, "governor");
    const debtRatio = configParams?.debtRatio || "0";
    const externalDepositFee = configParams?.externalDepositFee || "0";
    // add strategy in poolAccountant
    // if deployer is governor
    if (deployer === governor) {
      console.log(chalk.yellow("Note: Deployer is governor"));
      const signer = await hre.ethers.provider.getSigner(deployer);
      const txResponse = await poolAccountant
        .connect(signer)
        .addStrategy(strategyAddress, debtRatio, externalDepositFee);
      const receipt = await txResponse.wait();
      const hash = (await receipt?.getTransaction())?.hash;
      console.log(`executing ${strategyName}.addStrategy (tx: ${hash})`);
      return;
    }

    // if deployer is NOT governor
    const txnData = (
      await poolAccountant.addStrategy.populateTransaction(strategyAddress, debtRatio, externalDepositFee)
    ).data;

    const rawTx = { from: governor, to: paAddress, value: "0", data: txnData };

    const logMsg = {
      from: rawTx.from,
      to: rawTx.to,
      method: "addStrategy",
      args: [strategyAddress, debtRatio, externalDepositFee],
    };

    console.log(chalk.yellow("Transaction:"), JSON.stringify(logMsg, null, 2));
    console.log(chalk.yellow("Note: Above transaction is saved and it will be executed by safe later in the flow."));

    return saveForSafeBatchExecution(rawTx);
  }
}

export const deployAndConfigureStrategy = async (deployParams: DeployParams, configParams?: ConfigParams) => {
  const { execute, read } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const { alias } = deployParams;

  const deployed = await deploy(hre, deployParams);
  const strategyAddress = deployed.address;

  // Approve tokens
  const vesperPool = await read(alias, "pool");
  const collateralTokenAddress = await read(alias, "collateralToken");
  const collateralToken = await hre.ethers.getContractAt("IERC20", collateralTokenAddress);
  const allowance = await collateralToken.allowance(strategyAddress, vesperPool);
  // Allowance of collateralToken to pool is one of the key approval, so if it is zero then execute approveToken.
  if (allowance === 0n) {
    await execute(alias, { from: deployer, log: true }, "approveToken", hre.ethers.MaxUint256);
  }

  // Add keeper
  const governor = await read(alias, "governor");
  const keeper = configParams?.keeper || Address.Vesper.KEEPER;
  const keepers = await read(alias, "keepers");
  if (!keepers.includes(hre.ethers.getAddress(keeper))) {
    const executeFunction = () => execute(alias, { from: governor, log: true }, "addKeeper", keeper);
    await executeOrStoreTxIfMultisig(hre, executeFunction);
  }

  await addStrategy(hre, alias, strategyAddress, configParams);

  if (!["hardhat", "localhost"].includes(hre.network.name)) {
    await hre.run("verify:verify", { address: strategyAddress });
  }
};
