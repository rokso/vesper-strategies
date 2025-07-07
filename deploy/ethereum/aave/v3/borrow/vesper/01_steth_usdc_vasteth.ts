import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../../../helpers/deploy-helpers";
import Addresses from "../../../../../../helpers/address";
import { AAVE_V3_VESPER_BORROW_FOR_STETH } from "../../../../../../helpers/deploy-config";

const strategyName = "AaveV3_Vesper_Borrow_stETH_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: AAVE_V3_VESPER_BORROW_FOR_STETH,
    proxy: {
      initializeArgs: [
        Address.Vesper.vastETH,
        Address.swapper,
        Address.Aave.V3.aEthwstETH,
        Address.USDC,
        Address.Aave.V3.poolAddressesProvider,
        Address.Vesper.vaUSDC,
        Address.wstETH,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
