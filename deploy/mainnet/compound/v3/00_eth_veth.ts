import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../helpers/deploy-helpers";
import { COMPOUND_V3 } from "../../../../helpers/deploy-config";
import Addresses from "../../../../helpers/address";

const strategyName = "CompoundV3_ETH";
const alias = `${strategyName}_vETH`;

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  await deployAndConfigureStrategy({
    alias: alias,
    contract: COMPOUND_V3,
    proxy: {
      initializeArgs: [
        Address.Vesper.vETH,
        Address.swapper,
        Address.Compound.V3.rewards,
        Address.COMP,
        Address.Compound.V3.cWETHv3,
        strategyName,
      ],
    },
  });
};

func.tags = [alias];
export default func;
