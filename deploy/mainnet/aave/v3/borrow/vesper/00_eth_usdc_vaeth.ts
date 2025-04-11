import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../../../helpers/deploy-helpers";
import Addresses from "../../../../../../helpers/address";
import { AAVE_V3_VESPER_BORROW } from "../../../../../../helpers/deploy-config";

const strategyName = "AaveV3_Vesper_Borrow_ETH_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: AAVE_V3_VESPER_BORROW,
    proxy: {
      initializeArgs: [
        Address.Vesper.vaETH,
        Address.swapper,
        Address.Aave.V3.aEthWETH,
        Address.USDC,
        Address.Aave.V3.poolAddressesProvider,
        Address.Vesper.vaUSDC,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
