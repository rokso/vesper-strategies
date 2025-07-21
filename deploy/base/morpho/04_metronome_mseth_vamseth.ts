import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import { MORPHO_VAULT } from "../../../helpers/deploy-config";
import Addresses from "../../../helpers/address";

const strategyName = "Morpho_Metronome_msETH";

const func: DeployFunction = async function () {
  const Address = Addresses.base;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: MORPHO_VAULT,
    proxy: {
      initializeArgs: [Address.Vesper.vamsETH, Address.swapper, Address.Morpho.vault.Metronome_msETH, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
