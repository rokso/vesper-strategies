import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../../../helpers/deploy-helpers";
import Addresses from "../../../../../../helpers/address";
import { FRAXLEND_V1_VESPER_BORROW } from "../../../../../../helpers/deploy-config";

const strategyName = "FraxlendV1_Vesper_Borrow_WBTC_FRAX";

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: FRAXLEND_V1_VESPER_BORROW,
    proxy: {
      initializeArgs: [
        Address.Vesper.vaWBTC,
        Address.swapper,
        Address.Fraxlend.V1.WBTC_FRAX,
        Address.FRAX,
        Address.Vesper.vaFRAX,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
