/* eslint-disable @typescript-eslint/no-explicit-any */
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployResult, type Deployment } from "hardhat-deploy/types";
import { executeOrStoreTxIfMultisig } from "./deploy-helpers";
import { makeValidateUpgrade } from "@openzeppelin/hardhat-upgrades/dist/validate-upgrade";

// See `ERC1967Utils.sol` lib
const IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

export type DeployParams = {
  alias: string;
  contract: string;
  proxy: {
    methodName?: string;
    initializeArgs: any[];
  };
};

const validateUpgrade = async (
  hre: HardhatRuntimeEnvironment,
  oldImplDeployment: Deployment,
  contract: string,
): Promise<void> => {
  const oldImplFactory = await hre.ethers.getContractFactory(
    oldImplDeployment.abi,
    hre.ethers.getBytes(oldImplDeployment.bytecode!),
  );
  const newImplFactory = await hre.ethers.getContractFactory(contract);
  // If new storage layout is incompatible then it will throw error
  await makeValidateUpgrade(hre)(oldImplFactory, newImplFactory, {
    kind: "uups",
  });
};

const getImplementation = async (hre: HardhatRuntimeEnvironment, proxyAddress: string): Promise<string> => {
  const implementationStorage = await hre.ethers.provider.getStorage(proxyAddress, IMPLEMENTATION_SLOT);
  const implementationAddress = hre.ethers.getAddress(`0x${implementationStorage.slice(-40)}`);
  return implementationAddress;
};

export const deploy = async (hre: HardhatRuntimeEnvironment, params: DeployParams): Promise<DeployResult> => {
  const { getNamedAccounts, deployments } = hre;
  const { deploy, save, read, execute, getOrNull } = deployments;
  const { deployer } = await getNamedAccounts();

  if (!deployer) throw Error(`The 'deployer' named account wasn't set`);

  const { alias, contract, proxy } = params;
  const { methodName, initializeArgs } = proxy!;

  const implementationAlias = `${contract}_Implementation`;

  // Note: We are reading deployment from json file that corresponds to `alias` and not `implementationAlias`.
  // The reason being, `alias` is being created for each deployment and will not change until upgrade happens while
  // `implementationAlias` hold information in context of common implementation deployment and it will be updated
  // with each new deployment due to change in solidity code.
  const oldImplDeployment = await getOrNull(alias);
  if (oldImplDeployment) {
    await validateUpgrade(hre, oldImplDeployment, contract);
  }

  const implementationDeployment = await deploy(implementationAlias, {
    contract: contract,
    from: deployer,
    log: true,
  });

  const { address: implementationAddress } = implementationDeployment;

  const proxyAlias = `${alias}_Proxy`;

  let proxyDeployment: Deployment | null = await getOrNull(proxyAlias);

  if (!proxyDeployment) {
    // Get deployed implementation contract
    const implContract = await hre.ethers.getContract(implementationAlias);
    const initializeMethodName = methodName || "initialize";
    const encodedInitializeCall = implContract.interface.encodeFunctionData(initializeMethodName, initializeArgs || []);
    const constructorArgs = [implementationAddress, encodedInitializeCall];

    // Deploy `ERC1967Proxy`
    proxyDeployment = await deploy(proxyAlias, {
      contract: "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
      args: constructorArgs,
      from: deployer,
      log: true,
    });

    // Save proxy deployment file with proxy abi
    await save(proxyAlias, {
      ...proxyDeployment,
      implementation: implementationAddress,
      args: constructorArgs,
    });

    // Save `alias` deployment file with implementation deploy details but has proxy address as deployed address
    await save(alias, {
      ...implementationDeployment,
      address: proxyDeployment.address,
      implementation: implementationAddress,
    });

    if (!["hardhat", "localhost"].includes(hre.network.name)) {
      await hre.run("verify:verify", { address: proxyDeployment.address, constructorArguments: constructorArgs });
    }

    return { ...proxyDeployment, newlyDeployed: true };
  }

  // Update deployment file if needed
  if (proxyDeployment.implementation != implementationAddress) {
    // update implementation address in proxy deployment
    await save(proxyAlias, {
      ...proxyDeployment,
      implementation: implementationAddress,
    });
    // update implementation deployment
    await save(alias, {
      ...implementationDeployment,
      address: proxyDeployment.address,
      implementation: implementationAddress,
    });
  }

  const proxyImplementationAddress = await getImplementation(hre, proxyDeployment.address);

  // Upgrade proxy if needed
  if (oldImplDeployment && proxyImplementationAddress != hre.ethers.getAddress(implementationAddress)) {
    const governor = await read(alias, "governor");
    const executeFunction = () =>
      execute(alias, { from: governor, log: true }, "upgradeToAndCall", implementationAddress, "0x");
    await executeOrStoreTxIfMultisig(hre, executeFunction);
  }

  return { ...proxyDeployment, newlyDeployed: false };
};
