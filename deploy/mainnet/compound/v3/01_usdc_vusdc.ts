import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../helpers/deploy-helpers";
import { COMPOUND_V3 } from "../../../../helpers/deploy-config";
import Addresses from "../../../../helpers/address";

const strategyName = "CompoundV3_USDC";
const alias = `${strategyName}_vUSDC`;

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  await deployAndConfigureStrategy({
    alias: alias,
    contract: COMPOUND_V3,
    proxy: {
      initializeArgs: [
        Address.Vesper.vUSDC,
        Address.swapper,
        Address.Compound.V3.rewards,
        Address.COMP,
        Address.Compound.V3.cUSDCv3,
        strategyName,
      ],
    },
  });
};

func.tags = [alias];
export default func;
