import { ZeroAddress } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigureStrategy } from "../../../helpers/deploy-helpers";
import Addresses from "../../../helpers/address";
import { CONVEX } from "../../../helpers/deploy-config";

const strategyName = "Convex_ynETHx_ETH";

const func: DeployFunction = async function () {
  const Address = Addresses.mainnet;

  const curveInitParams = {
    pool: Address.Vesper.vaETH,
    swapper: Address.swapper,
    curvePool: Address.Curve.ynETHx_ETH_POOL,
    curvePoolZap: ZeroAddress, // no zap needed
    depositAndStake: Address.Curve.DepositAndStake,
    useDynamicArray: true,
    slippage: 200, // 2%
    weth: Address.WETH,
    masterOracle: Address.masterOracle,
    name: strategyName,
  };

  await deployAndConfigureStrategy({
    alias: strategyName,
    contract: CONVEX,
    proxy: {
      // Pass initParam struct as is and then pass convex specific params
      initializeArgs: [curveInitParams, Address.Convex.booster, 418],
    },
  });
};

func.tags = [strategyName];
export default func;
