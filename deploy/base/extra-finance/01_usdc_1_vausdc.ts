import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import { EXTRA_FINANCE } from "../../../helpers/deploy-config";
import Addresses from "../../../helpers/address";

const strategyName = "ExtraFinance_Pool1_USDC";

const func: DeployFunction = async function () {
  const Address = Addresses.base;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: EXTRA_FINANCE,
    proxy: {
      initializeArgs: [Address.Vesper.vaUSDC, Address.swapper, Address.ExtraFinance.LendingPool, 25, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
