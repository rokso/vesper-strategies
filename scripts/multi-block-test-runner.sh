#!/bin/bash

# Add color variables at the top
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NF=$PURPLE$BOLD # 'network' formatter
RESET='\033[0m' # reset formatting

# Source the environment variables
source .env

# Function to get current block number
get_current_block_number() {
    local node_url=$1
    local result=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$node_url")

    # Check if curl request was successful
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    local hex_block=$(echo "$result" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$hex_block" ]]; then
        return 1
    fi

    echo $((16#${hex_block#0x})) # Convert hex to decimal
    return 0
}

# Function to run tests for a network
run_network_tests() {
    local network=$1
    local node_url=$2
    local current_block_number

    echo -e "Checking ${NF}$network${RESET} network..."

    # Get current block number
    current_block_number=$(get_current_block_number "$node_url")
    if [[ $? -ne 0 ]]; then
        echo "Skipping $network: Failed to fetch current block number"
        return
    fi

    echo -e "Current ${NF}$network${RESET} block number: ${GREEN}$current_block_number${RESET}"

    # Generate test parameters
    local random_number=$((RANDOM % 4 + 2)) # random number between 2 and 5
    local block_chunk_size=$((1000 / random_number))
    local iterations=$((random_number + 1))
    echo -e "\nRandom generated tests parameters:"
    echo "block_chunk_size = $block_chunk_size"
    echo "Number of iterations: $iterations"

    echo -e "\nRunning tests for ${NF}$network${RESET}..."
    for ((i = 0; i < iterations; i++)); do
        fork_block_number=$((current_block_number - (i * block_chunk_size)))
        echo -e "Iteration ${GREEN}$i${RESET}: Using fork_block_number=${GREEN}$fork_block_number${RESET}"
        forge test --fork-url $node_url --fork-block-number $fork_block_number --mp $network
    done
    echo -e "Completed tests for ${NF}$network${RESET}"
    echo "-----------------------------"
}

# Check and run tests for each network
networks=("ethereum" "base" "optimism")
node_urls=("$MAINNET_FORK_NODE_URL" "$BASE_FORK_NODE_URL" "$OPTIMISM_FORK_NODE_URL")

# Run tests for each available network
for i in "${!networks[@]}"; do
    if [[ -n "${node_urls[$i]}" ]]; then
        run_network_tests "${networks[$i]}" "${node_urls[$i]}"
    else
        echo -e "${YELLOW}Skipping ${NF}${networks[$i]}${YELLOW}: RPC URL not found in .env${RESET}"
    fi
done

echo -e "${GREEN}All tests completed!${RESET}"
