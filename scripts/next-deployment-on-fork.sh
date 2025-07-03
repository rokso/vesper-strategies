#!/bin/bash

network=$1

if [[ "$network" == "" ]]; then
    echo "Use: $0 <network>"
    exit
fi

if [[ "$network" != "ethereum" && "$network" != "optimism" && "$network" != "base" ]]; then
    echo "'$network' is invalid"
    exit
fi

# Prepare deployment data
cp -r deployments/$network deployments/localhost

# Impersonate accounts (e.g. multisig)
npx hardhat impersonate --network localhost

# Deployment
npx hardhat deploy --network localhost
