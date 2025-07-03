import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../helpers/deploy-helpers";
import { AAVE_V3 } from "../../../../helpers/deploy-config";
import Addresses from "../../../../helpers/address";

const strategyName = "AaveV3_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: AAVE_V3,
    proxy: {
      initializeArgs: [
        Address.Vesper.vaUSDC,
        Address.swapper,
        Address.Aave.V3.aEthUSDC,
        Address.Aave.V3.poolAddressesProvider,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
