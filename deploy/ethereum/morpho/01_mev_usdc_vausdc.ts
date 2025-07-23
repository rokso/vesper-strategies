import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import { MORPHO_VAULT } from "../../../helpers/deploy-config";
import Addresses from "../../../helpers/address";

const strategyName = "Morpho_MEV_Capital_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: MORPHO_VAULT,
    proxy: {
      initializeArgs: [Address.Vesper.vaUSDC, Address.swapper, Address.Morpho.vault.MEV_Capital_USDC, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
