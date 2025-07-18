import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../helpers/deploy-helpers";
import { COMPOUND_V3 } from "../../../../helpers/deploy-config";
import Addresses from "../../../../helpers/address";

const strategyName = "CompoundV3_ETH";

const func: DeployFunction = async function () {
  const Address = Addresses.optimism;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: COMPOUND_V3,
    proxy: {
      initializeArgs: [
        Address.Vesper.vaETH,
        Address.swapper,
        Address.Compound.V3.rewards,
        Address.COMP,
        Address.Compound.V3.cWETHv3,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
