import { HardhatUserConfig } from "hardhat/types";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "dotenv/config";
import "./tasks/create-release";
import "./tasks/impersonate";

const localhost = process.env.FORK_NODE_URL || "http://localhost:8545";
const mainnetNodeUrl = process.env.MAINNET_NODE_URL || "";
const optimismNodeUrl = process.env.OPTIMISM_NODE_URL || "";
const baseNodeUrl = process.env.BASE_NODE_URL || "";

function getChainConfig(nodeUrl: string) {
  if (["eth.connect", "eth-mainnet", "mainnet.infura"].some((v) => nodeUrl.includes(v))) {
    return { chainId: 1, deploy: ["deploy/mainnet"] };
  }

  if (["optimism", "opt-mainnet"].some((v) => nodeUrl.includes(v))) {
    return { chainId: 10, deploy: ["deploy/optimism"] };
  }

  if (nodeUrl.includes("base")) {
    return { chainId: 8453, deploy: ["deploy/base"] };
  }

  return { chainId: 31337, deploy: ["deploy/mainnet"] };
}

function getFork() {
  const nodeUrl = process.env.FORK_NODE_URL;
  return nodeUrl
    ? {
        initialBaseFeePerGas: 0,
        forking: {
          url: nodeUrl,
          blockNumber: process.env.FORK_BLOCK_NUMBER ? parseInt(process.env.FORK_BLOCK_NUMBER) : undefined,
        },
        chains: {
          // See: https://hardhat.org/hardhat-network/docs/guides/forking-other-networks#using-a-custom-hardfork-history
          8453: { hardforkHistory: { cancun: 1 } },
        },
        ...getChainConfig(nodeUrl),
      } // eslint-disable-next-line @typescript-eslint/no-explicit-any
    : ({} as any);
}

let accounts;
if (process.env.MNEMONIC) {
  accounts = { mnemonic: process.env.MNEMONIC };
}

if (process.env.PRIVATE_KEY) {
  accounts = [process.env.PRIVATE_KEY];
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: getFork(),
    localhost: {
      accounts,
      saveDeployments: true,
      ...getChainConfig(localhost),
      autoImpersonate: true,
    },
    mainnet: {
      url: mainnetNodeUrl,
      accounts,
      ...getChainConfig(mainnetNodeUrl),
    },
    optimism: {
      url: optimismNodeUrl,
      accounts,
      ...getChainConfig(optimismNodeUrl),
    },
    base: {
      url: baseNodeUrl,
      accounts,
      ...getChainConfig(baseNodeUrl),
    },
  },

  sourcify: {
    enabled: false,
  },

  etherscan: {
    enabled: true, // process.env.FORK_NODE_URL ? false : true,
    apiKey: {
      mainnet: process.env.MAINNET_ETHERSCAN_API_KEY || "",
      optimism: process.env.OPTIMISM_ETHERSCAN_API_KEY || "",
      base: process.env.BASE_ETHERSCAN_API_KEY || "",
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org",
          browserURL: "https://basescan.org/",
        },
      },
    ],
  },

  namedAccounts: {
    deployer: process.env.DEPLOYER || 0,
  },

  contractSizer: {
    runOnCompile: process.env.RUN_CONTRACT_SIZER === "true" ? true : false,
  },

  solidity: {
    version: "0.8.25",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
    },
  },

  mocha: {
    timeout: 400000,
  },
};

export default config;
