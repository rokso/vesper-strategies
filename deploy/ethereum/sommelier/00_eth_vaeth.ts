import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import { SOMMELIER } from "../../../helpers/deploy-config";
import Addresses from "../../../helpers/address";

const strategyName = "Sommelier_ETH";

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: SOMMELIER,
    proxy: {
      initializeArgs: [Address.Vesper.vaETH, Address.swapper, Address.Sommelier.YieldETH, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
