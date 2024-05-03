#!/bin/bash
set -e

# Parse command line arguments for the 'profile-type', 'binary-version', and 'profile-duration' flags
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile-type) profile_type="$2"; shift ;;
        --binary-version) binary_version="$2"; shift ;;
        --profile-duration) profile_duration="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Default to a specific profile type if none is provided
if [ -z "$profile_type" ]; then
    echo "No profile type specified, defaulting to 'head'"
    profile_type="head"
fi

# Default to a specific profile duration if none is provided and profile type is 'head'
if [ "$profile_type" == "head" ] && [ -z "$profile_duration" ]; then
    echo "No profile duration specified, defaulting to '60'"
    profile_duration="60"
fi
# # Default to a specific binary version if none is provided
# if [ -z "$binary_version" ]; then
#     echo "No binary version specified, defaulting to '22.0.5'"
#     binary_version="22.0.5"
# fi

MONIKER=osmosis
OSMOSIS_HOME=/root/.osmosisd

MAINNET_DEFAULT_VERSION="22.0.5"
# Determine the MAINNET_SNAPSHOT_URL based on the profile type
if [ "$profile_type" == "head" ]; then
    MAINNET_SNAPSHOT_URL=$(curl -sL https://snapshots.osmosis.zone/latest)
else
    # TODO: Add support for other profile types
    # MAINNET_SNAPSHOT_URL=$(curl -sL https://snapshots.osmosis.zone/latest)
    :
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
    elif [ ! -z "$binary_version" ]; then
        echo "Setting version to $binary_version"
        VERSION=$binary_version
    else
        echo "Setting version to $NETWORK_VERSION"
        VERSION=$NETWORK_VERSION
    fi
fi

if [ -z "$binary_version" ]; then
    echo "No binary version specified, defaulting to RPC version: $VERSION"
    BINARY_URL="https://osmosis.fra1.digitaloceanspaces.com/binaries/v$VERSION/osmosisd-$VERSION-linux-amd64"
    echo "🔽 Downloading Osmosis binary from $BINARY_URL..."
    wget -q $BINARY_URL -O /usr/local/bin/osmosisd-$VERSION 

    chmod +x /usr/local/bin/osmosisd-$VERSION
    echo "✅ Osmosis binary downloaded successfully."
else
    git clone https://github.com/osmosis-labs/osmosis.git
    cd /root/osmosis
    git checkout $VERSION
    VERSION=${VERSION//\//-}
    make build
    cp build/osmosisd /usr/local/bin/osmosisd-$VERSION
    chmod +x /usr/local/bin/osmosisd-$VERSION
    echo "✅ Osmosis binary built and copied successfully."
    cd /root
fi


# echo -e "\n$YELLOW📜 Checking that /usr/local/bin/osmosisd-$VERSION exists$RESET"
# if [ ! -f /usr/local/bin/osmosisd-$VERSION ] || [[ "$(/usr/local/bin/osmosisd-$VERSION version --home /tmp/.osmosisd 2>&1)" != $VERSION ]]; then

#     BINARY_URL="https://osmosis.fra1.digitaloceanspaces.com/binaries/v$VERSION/osmosisd-$VERSION-linux-amd64"
#     echo "🔽 Downloading Osmosis binary from $BINARY_URL..."
#     wget -q $BINARY_URL -O /usr/local/bin/osmosisd-$VERSION 

#     chmod +x /usr/local/bin/osmosisd-$VERSION
#     echo "✅ Osmosis binary downloaded successfully."
# fi


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
wget -q $GENESIS_URL -O $OSMOSIS_HOME/config/genesis.json
echo ✅ Genesis file downloaded successfully.


# Download addrbook
echo -e "\n$YELLOW🔽 Downloading addrbook...$RESET"
wget -q $ADDRBOOK_URL -O $OSMOSIS_HOME/config/addrbook.json
echo ✅ Addrbook downloaded successfully.


# Download latest snapshot
echo -e "\n$YELLOW🔽 Downloading latest snapshot...$RESET"
wget -q -O - $SNAPSHOT_URL | lz4 -d | tar -C $OSMOSIS_HOME/ -xf -
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

if [ "$profile_type" == "head" ]; then
    echo -n "Waiting for catching_up to be false and block height to change"
    until [ $(curl -s http://localhost:26657/status | jq -r '.result.sync_info.catching_up') == "false" ]; do
        printf '.'
        sleep 1
        if ! ps -p $PID > /dev/null; then
            echo "Osmosis process is no longer running. Exiting."
            exit 1
        fi
    done

    # Get the current block height
    current_block_height=$(curl -s http://localhost:26657/status | jq -r '.result.sync_info.latest_block_height')

    # Wait for 5 seconds
    sleep 5

    # Get the new block height
    new_block_height=$(curl -s http://localhost:26657/status | jq -r '.result.sync_info.latest_block_height')

    # Check if the block height has changed
    if [ "$current_block_height" == "$new_block_height" ]; then
        echo "Block height has not changed after 5 seconds. Exiting."
        exit 1
    fi

    echo "Block height has changed. Success."

    # Calculate the curl maximum time
    curl_max_time=$((profile_duration + 10))

    # Curl the CPU and heap endpoints simultaneously and store the profiles
    curl -m $curl_max_time -X GET "localhost:6060/debug/pprof/profile?seconds=$profile_duration" > cpu.prof &
    pid_cpu=$!
    curl -m $curl_max_time -X GET "localhost:6060/debug/pprof/heap?seconds=$profile_duration" > heap.prof &
    pid_heap=$!
    curl -m $curl_max_time -X GET "localhost:6060/debug/pprof/block?seconds=$profile_duration" > block.prof &
    pid_block=$!
    curl -m $curl_max_time -X GET "localhost:6060/debug/pprof/mutex?seconds=$profile_duration" > mutex.prof &
    pid_mutex=$!

    wait $pid_cpu
    echo "CPU profiling completed."

    wait $pid_heap
    echo "Heap profiling completed."

    wait $pid_block
    echo "Block profiling completed."

    wait $pid_mutex
    echo "Mutex profiling completed."

    # Upload the profiles to bashupload.com and get the file links
     echo "Uploading profiles to bashupload.com..."
    cpu_prof_link=$(curl bashupload.com -T cpu.prof | grep -o 'http://bashupload.com/[^ ]*')
    heap_prof_link=$(curl bashupload.com -T heap.prof | grep -o 'http://bashupload.com/[^ ]*')
    block_prof_link=$(curl bashupload.com -T block.prof | grep -o 'http://bashupload.com/[^ ]*')
    mutex_prof_link=$(curl bashupload.com -T mutex.prof | grep -o 'http://bashupload.com/[^ ]*')

    # Print the file links as output parameters
    echo "::set-output name=cpu_prof_link::$cpu_prof_link"
    echo "::set-output name=heap_prof_link::$heap_prof_link"
    echo "::set-output name=block_prof_link::$block_prof_link"
    echo "::set-output name=mutex_prof_link::$mutex_prof_link"

else
    # TODO: Add support for other profile types
    :
fi

echo -e "\n\n✅ Osmosis node has started successfully. (PID: $PURPLE$PID$RESET)\n"

echo "-------------------------------------------------"
echo -e 🔍 Run$YELLOW osmosisd status$RESET to check sync status.
echo -e 📄 Check logs with$YELLOW tail -f /root/osmosisd.log$RESET
echo -e 🛑 Stop node with$YELLOW kill -INT $PID$RESET
echo "-------------------------------------------------"