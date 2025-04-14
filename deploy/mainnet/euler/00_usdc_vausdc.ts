import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import { EULER_V2 } from "../../../helpers/deploy-config";
import Addresses from "../../../helpers/address";

const strategyName = "EulerV2_Euler_Prime_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: EULER_V2,
    proxy: {
      initializeArgs: [Address.Vesper.vaUSDC, Address.swapper, Address.EulerV2.eUSDC2, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
