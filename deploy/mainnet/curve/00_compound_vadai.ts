import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import Addresses from "../../../helpers/address";
import { CURVE } from "../../../helpers/deploy-config";

const strategyName = "Curve_Compound_DAI";

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  const curveInitParams = {
    pool: Address.Vesper.vaDAI,
    swapper: Address.swapper,
    curvePool: Address.Curve.Compound_Pool,
    curvePoolZap: Address.Curve.Compound_Pool_Zap,
    depositAndStake: Address.Curve.DepositAndStake,
    useDynamicArray: false,
    slippage: 200, // 2%
    weth: Address.WETH,
    masterOracle: Address.masterOracle,
    name: strategyName,
  };

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: CURVE,
    proxy: {
      // Curve initialize function expect struct as is.
      initializeArgs: [curveInitParams],
    },
  });
};

func.tags = [strategyName];
export default func;
