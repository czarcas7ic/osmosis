#!/bin/bash
set -e

# Parse command line arguments for the 'profile-type' flag
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile-type) profile_type="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Default to a specific profile type if none is provided
if [ -z "$profile_type" ]; then
    echo "No profile type specified, defaulting to 'head'"
    profile_type="head"
fi

MONIKER=osmosis
OSMOSIS_HOME=/root/.osmosisd

MAINNET_DEFAULT_VERSION="22.0.5"
# Determine the MAINNET_SNAPSHOT_URL based on the profile type
if [ "$profile_type" == "head" ]; then
    MAINNET_SNAPSHOT_URL=$(curl -sL https://snapshots.osmosis.zone/latest)
else
    # TODO: Add support for other profile types
    # MAINNET_SNAPSHOT_URL=$(curl -sL https://snapshots.osmosis.zone/latest)
fi
MAINNET_RPC_URL=https://rpc.osmosis.zone
MAINNET_ADDRBOOK_URL="https://rpc.osmosis.zone/addrbook"
MAINNET_GENESIS_URL=https://github.com/osmosis-labs/osmosis/raw/main/networks/osmosis-1/genesis.json

TESTNET_DEFAULT_VERSION="22.0.0-rc0"
TESTNET_SNAPSHOT_URL=$(curl -sL https://snapshots.testnet.osmosis.zone/latest)
TESTNET_RPC_URL=https://rpc.testnet.osmosis.zone
TESTNET_ADDRBOOK_URL="https://rpc.testnet.osmosis.zone/addrbook"
TESTNET_GENESIS_URL="https://genesis.testnet.osmosis.zone/genesis.json"

# Set mainnet as default
CHAIN_ID=${1:-osmosis-1}

VERSION=$MAINNET_DEFAULT_VERSION
SNAPSHOT_URL=$MAINNET_SNAPSHOT_URL
ADDRBOOK_URL=$MAINNET_ADDRBOOK_URL
GENESIS_URL=$MAINNET_GENESIS_URL
RPC_URL=$MAINNET_RPC_URL

# Define color environment variables
YELLOW='\033[33m'
RESET='\033[0m'
PURPLE='\033[35m'

case "$CHAIN_ID" in
    osmosis-1)
        echo -e "\n🧪 $PURPLE Joining 'osmosis-1' network...$RESET"
        ;;
    osmo-test-5)
        echo -e "\n🧪 $PURPLE Joining 'osmo-test-5' network...$RESET"
        SNAPSHOT_URL=$TESTNET_SNAPSHOT_URL
        ADDRBOOK_URL=$TESTNET_ADDRBOOK_URL
        GENESIS_URL=$TESTNET_GENESIS_URL
        RPC_URL=$TESTNET_RPC_URL
        VERSION=$TESTNET_DEFAULT_VERSION
        ;;
    *)
        echo "Invalid Chain ID. Acceptable values are 'osmosis-1' and 'osmo-test-5'."
        exit 1
        ;;
esac

echo -e "\n$YELLOW🚨 Ensuring that no osmosisd process is running$RESET"
if pgrep -f "osmosisd start" >/dev/null; then
    echo "An 'osmosisd' process is already running."

    read -p "Do you want to stop and delete the running 'osmosisd' process? (y/n): " choice
    case "$choice" in
        y|Y )
            pkill -INT -f "osmosisd start --home /root/.osmosisd"
            echo "The running 'osmosisd' process has been stopped and deleted."
            ;;
        * )
            echo "Exiting the script without stopping or deleting the 'osmosisd' process."
            exit 1
            ;;
    esac
fi

echo -e "\n$YELLOW🔎 Getting current network version from $RPC_URL...$RESET"
RPC_ABCI_INFO=$(curl -s --retry 5 --retry-delay 1 --connect-timeout 3 -H "Accept: application/json" $RPC_URL/abci_info) || true

if [ -z "$RPC_ABCI_INFO" ]; then
    echo "Can't contact $RPC_URL, using default version: $VERSION"
else
    NETWORK_VERSION=$(echo $RPC_ABCI_INFO | dasel --plain -r json  'result.response.version') || true

    if [ -z "$NETWORK_VERSION" ]; then
        echo "Can't contact $RPC_URL, using default version: $VERSION"
    else
        echo "Setting version to $NETWORK_VERSION"
        VERSION=$NETWORK_VERSION
    fi
fi

echo -e "\n$YELLOW📜 Checking that /usr/local/bin/osmosisd-$VERSION exists$RESET"
if [ ! -f /usr/local/bin/osmosisd-$VERSION ] || [[ "$(/usr/local/bin/osmosisd-$VERSION version --home /tmp/.osmosisd 2>&1)" != $VERSION ]]; then

    BINARY_URL="https://osmosis.fra1.digitaloceanspaces.com/binaries/v$VERSION/osmosisd-$VERSION-linux-amd64"
    echo "🔽 Downloading Osmosis binary from $BINARY_URL..."
    wget $BINARY_URL -O /usr/local/bin/osmosisd-$VERSION 

    chmod +x /usr/local/bin/osmosisd-$VERSION
    echo "✅ Osmosis binary downloaded successfully."
fi


echo -e "\n$YELLOW📜 Checking that /usr/local/bin/osmosisd is a symlink to /usr/local/bin/osmosisd-$VERSION otherwise create it$RESET"
if [ ! -L /usr/local/bin/osmosisd ] || [ "$(readlink /usr/local/bin/osmosisd)" != "/usr/local/bin/osmosisd-$VERSION" ]; then
    ln -sf /usr/local/bin/osmosisd-$VERSION /usr/local/bin/osmosisd
    chmod +x /usr/local/bin/osmosisd
    echo ✅ Symlink created successfully.
fi


# Clean osmosis home
echo -e "\n$YELLOW🗑️ Removing existing Osmosis home directory...$RESET"
if [ -d "$OSMOSIS_HOME" ]; then
    read -p "Are you sure you want to delete $OSMOSIS_HOME? (y/n): " choice
    case "$choice" in 
        y|Y ) 
            rm -rf $OSMOSIS_HOME;;
        * ) echo "Osmosis home directory deletion canceled."
            exit 1
            ;;
    esac
fi


# Initialize osmosis home
echo -e "\n$YELLOW🌱 Initializing Osmosis home directory...$RESET"
osmosisd init $MONIKER


# Copy configs
echo -e "\n$YELLOW📋 Copying client.toml, config.toml, and app.toml...$RESET"
cp /etc/osmosis/client.toml $OSMOSIS_HOME/config/client.toml
cp /etc/osmosis/config.toml $OSMOSIS_HOME/config/config.toml
cp /etc/osmosis/app.toml $OSMOSIS_HOME/config/app.toml


# Copy genesis
echo -e "\n$YELLOW🔽 Downloading genesis file...$RESET"
wget $GENESIS_URL -O $OSMOSIS_HOME/config/genesis.json
echo ✅ Genesis file downloaded successfully.


# Download addrbook
echo -e "\n$YELLOW🔽 Downloading addrbook...$RESET"
wget $ADDRBOOK_URL -O $OSMOSIS_HOME/config/addrbook.json
echo ✅ Addrbook downloaded successfully.


# Download latest snapshot
echo -e "\n$YELLOW🔽 Downloading latest snapshot...$RESET"
wget -O - $SNAPSHOT_URL | lz4 -d | tar -C $OSMOSIS_HOME/ -xf -
echo -e ✅ Snapshot downloaded successfully.


# Starting binary
echo -e "\n$YELLOW🚀 Starting Osmosis node...$RESET"
nohup osmosisd start --home ${OSMOSIS_HOME} > /root/osmosisd.log 2>&1 &
PID=$!


# Waiting for node to complete initGenesis
echo -n "Waiting to hit first block"
until $(curl --output /dev/null --silent --head --fail http://localhost:26657/status) && [ $(curl -s http://localhost:26657/status | jq -r '.result.sync_info.latest_block_height') -ne 0 ]; do
printf '.'
sleep 1
if ! ps -p $PID > /dev/null; then
    echo "Osmosis process is no longer running. Exiting."
    exit 1
fi
done

echo -e "\n\n✅ Osmosis node has started successfully. (PID: $PURPLE$PID$RESET)\n"

echo "-------------------------------------------------"
echo -e 🔍 Run$YELLOW osmosisd status$RESET to check sync status.
echo -e 📄 Check logs with$YELLOW tail -f /root/osmosisd.log$RESET
echo -e 🛑 Stop node with$YELLOW kill -INT $PID$RESET
echo "-------------------------------------------------"