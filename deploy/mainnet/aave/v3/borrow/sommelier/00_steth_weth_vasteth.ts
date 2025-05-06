import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../../../helpers/deploy-helpers";
import Addresses from "../../../../../../helpers/address";
import { AAVE_V3_SOMMELIER_BORROW_FOR_STETH } from "../../../../../../helpers/deploy-config";

const strategyName = "AaveV3_Sommelier_Borrow_stETH_WETH";

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: AAVE_V3_SOMMELIER_BORROW_FOR_STETH,
    proxy: {
      methodName: "AaveV3SommelierBorrowForStETH_initialize",
      initializeArgs: [
        Address.Vesper.vastETH,
        Address.swapper,
        Address.Aave.V3.aEthwstETH,
        Address.WETH,
        Address.Aave.V3.poolAddressesProvider,
        Address.Sommelier.YieldETH,
        Address.wstETH,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
