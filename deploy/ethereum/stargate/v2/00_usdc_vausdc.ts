import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../helpers/deploy-helpers";
import { STARGATE_V2 } from "../../../../helpers/deploy-config";
import Addresses from "../../../../helpers/address";

const strategyName = "StargateV2_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: STARGATE_V2,
    proxy: {
      initializeArgs: [
        Address.Vesper.vaUSDC,
        Address.swapper,
        Address.Stargate.V2.usdcPool,
        Address.Stargate.V2.stargateStaking,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
