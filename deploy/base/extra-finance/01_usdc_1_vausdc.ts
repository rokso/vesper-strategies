import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import { EXTRA_FINANCE } from "../../../helpers/deploy-config";
import Addresses from "../../../helpers/address";

const strategyName = "ExtraFinance_USDC_1";

const func: DeployFunction = async function () {
  const Address = Addresses.base;

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: EXTRA_FINANCE,
    proxy: {
      initializeArgs: [Address.Vesper.vaUSDC, Address.swapper, Address.ExtraFinance.LendingPool, 24, strategyName],
    },
  });
};

func.tags = [strategyName];
export default func;
