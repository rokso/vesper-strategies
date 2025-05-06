import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import { YEARN } from "../../../helpers/deploy-config";
import Addresses from "../../../helpers/address";

const strategyName = "Yearn_ETH";

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: YEARN,
    proxy: {
      initializeArgs: [Address.Vesper.vaETH, Address.swapper, Address.Yearn.yvWETH, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
