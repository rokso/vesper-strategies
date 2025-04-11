#!/bin/bash

deployFlag=$1
if [[ "$deployFlag" == "" ]]; then
    echo "Use: $0 <--deploy|--no-deploy>"
    exit
fi
if [[ "$deployFlag" != "--deploy" && "$deployFlag" != "--no-deploy" ]]; then
    echo "'$deployFlag' is invalid"
    exit
fi

# Update ENV VARS
source .env

echo "Make sure .env has the correct values."
echo ""
echo FORK_NODE_URL=$FORK_NODE_URL
echo FORK_BLOCK_NUMBER=$FORK_BLOCK_NUMBER
echo ""
echo -n "Press <ENTER> to continue: "
read

# Clean old files
rm -rf artifacts/ cache_hardhat/ multisig.batch.tmp.json

if [[ "$deployFlag" == "--deploy" ]]; then
    echo "Starting forked node with deployments..."
    # Run node
    npx hardhat node --fork $FORK_NODE_URL --fork-block-number $FORK_BLOCK_NUMBER
else
    echo "Starting forked node without deployments..."
    # Run node
    npx hardhat node --fork $FORK_NODE_URL --fork-block-number $FORK_BLOCK_NUMBER --no-deploy
fi
