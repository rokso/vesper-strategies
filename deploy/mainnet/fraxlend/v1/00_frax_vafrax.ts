import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../helpers/deploy-helpers";
import { FRAXLEND_V1 } from "../../../../helpers/deploy-config";
import Addresses from "../../../../helpers/address";

const strategyName = "Fraxlend_sfrxETH_FRAX";

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: FRAXLEND_V1,
    proxy: {
      initializeArgs: [Address.Vesper.vaFRAX, Address.swapper, Address.Fraxlend.V1.sfrxETH_FRAX, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
