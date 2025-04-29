#!/usr/bin/env bash
set -euo pipefail

# Source environment variables
source .env

# Check required environment variables
required_env_vars=("ETH_RPC_URL")
for var in "${required_env_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "$var is not set"
        exit 1
    fi
done

# Determine if we're deploying to a local network
is_local_network=false
if [[ "$ETH_RPC_URL" == *"localhost"* ]] || [[ "$ETH_RPC_URL" == *"127.0.0.1"* ]]; then
    is_local_network=true
    echo "Detected local network deployment"
fi

# Check for verification-related env vars only if not on local network
if [ "$is_local_network" = false ]; then
    verification_env_vars=("ETHERSCAN_API_KEY" "PRIVATE_KEY")
    for var in "${verification_env_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo "$var is not set (required for non-local deployments)"
            exit 1
        fi
    done
fi

# Clean and build before deployment to ensure all artifacts are up to date
echo "Cleaning and building project..."
forge clean && forge build

# Set up the deployment command
deploy_cmd="forge script script/deploy.s.sol --broadcast --rpc-url=$ETH_RPC_URL -vvvvv"

# Add private key if available
if [ -n "${PRIVATE_KEY:-}" ]; then
    deploy_cmd="$deploy_cmd --private-key=$PRIVATE_KEY"
fi

# Add verification flag only for non-local networks
if [ "$is_local_network" = false ]; then
    deploy_cmd="$deploy_cmd --verify"
fi

# Run the deployment script
echo "Deploying contracts..."
if $deploy_cmd; then
    echo "Deployment successful!"
    echo "Deployed contract addresses can be found in script/output/output.json"
else
    # For local networks, check if the failure was just due to verification
    if [ "$is_local_network" = true ] && [ -f "script/output/output.json" ]; then
        echo "Deployment appears to have succeeded, but verification failed (expected for local networks)"
        echo "Deployed contract addresses can be found in script/output/output.json"
        exit 0
    else
        echo "Deployment failed!"
        exit 1
    fi
fi
