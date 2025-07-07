import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../../../../helpers/deploy-helpers";
import Addresses from "../../../../../../helpers/address";
import { COMPOUND_V3_VESPER_BORROW } from "../../../../../../helpers/deploy-config";

const strategyName = "CompoundV3_Vesper_Borrow_ETH_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: COMPOUND_V3_VESPER_BORROW,
    proxy: {
      initializeArgs: [
        Address.Vesper.vaETH,
        Address.swapper,
        Address.Compound.V3.rewards,
        Address.COMP,
        Address.Compound.V3.cUSDCv3,
        Address.USDC,
        Address.Vesper.vaUSDC,
        strategyName,
      ],
    },
  });
};

func.tags = [strategyName];
export default func;
