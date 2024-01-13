#!/usr/bin/env bash
# Start all processes necessary to create a local testnet

set -Eeuo pipefail

source ./vars.env

# Set a higher ulimit in case we want to import 1000s of validators.
ulimit -n 65536

# VC_COUNT is defaulted in vars.env
# STALE_BN_COUNT and TOTAL_COUNT are defaulted in vars.env
DEBUG_LEVEL=${DEBUG_LEVEL:-info}
BUILDER_PROPOSALS=
TOTAL_COUNT=$BN_COUNT+$STALE_BN_COUNT

# Get options
while getopts "v:d:ph" flag; do
  case "${flag}" in
    v) VC_COUNT=${OPTARG};;
    d) DEBUG_LEVEL=${OPTARG};;
    p) BUILDER_PROPOSALS="-p";;
    h)
        validators=$(( $VALIDATOR_COUNT / $TOTAL_COUNT ))
        echo "Start local testnet, defaults: 1 eth1 node, $BN_COUNT beacon nodes,"
        echo "$STALE_BN_COUNT stale nodes and $VC_COUNT validator clients with"
        echo "each vc having $validators validators."
        echo
        echo "usage: $0 <Options>"
        echo
        echo "Options:"
        echo "   -v: VC_COUNT    default: $VC_COUNT"
        echo "   -d: DEBUG_LEVEL default: info"
        echo "   -p:             enable builder proposals"
        echo "   -h:             this help"
        exit
        ;;
  esac
done

if (( $VC_COUNT > $TOTAL_COUNT )); then
    echo "Error $VC_COUNT is too large, must be <= TOTAL_COUNT=$TOTAL_COUNT"
    exit
fi

genesis_file=${@:$OPTIND+0:1}

# Init some constants
PID_FILE=$TESTNET_DIR/PIDS.pid
PID_FILE_STALE=$TESTNET_DIR/PIDS_STALE.pid
LOG_DIR=$TESTNET_DIR

# Stop local testnet and remove $PID_FILE
./stop_local_testnet.sh

# Clean $DATADIR and create empty log files so the
# user can "tail -f" right after starting this script
# even before its done.
./clean.sh
mkdir -p $LOG_DIR
for (( bn=1; bn<=$TOTAL_COUNT; bn++ )); do
    touch $LOG_DIR/beacon_node_$bn.log
done
for (( el=1; el<=$TOTAL_COUNT; el++ )); do
    touch $LOG_DIR/geth_$el.log
done
for (( vc=1; vc<=$VC_COUNT; vc++ )); do
    touch $LOG_DIR/validator_node_$vc.log
done

# Sleep with a message
sleeping() {
   echo sleeping $1
   sleep $1
}

# Execute the command with logs saved to a file.
#
# First parameter is log file name
# Second parameter is executable name
# Remaining parameters are passed to executable
execute_command() {
    LOG_NAME=$1
    EX_NAME=$2
    shift
    shift
    CMD="$EX_NAME $@ >> $LOG_DIR/$LOG_NAME 2>&1"
    echo "executing: $CMD"
    echo "$CMD" > "$LOG_DIR/$LOG_NAME"
    eval "$CMD &"
}

# Execute the command with logs saved to a file
# and is PID is saved to $PID_FILE.
#
# First parameter is log file name
# Second parameter is executable name
# Remaining parameters are passed to executable
execute_command_add_PID() {
    execute_command $@
    echo "$!" >> $PID_FILE
}

execute_command_add_PID_STALE() {
    execute_command $@
    echo "$!" >> $PID_FILE_STALE
}

# Setup data
echo "executing: ./setup.sh >> $LOG_DIR/setup.log"
./setup.sh >> $LOG_DIR/setup.log 2>&1

# Call setup_time.sh to update future hardforks time in the EL genesis file based on the CL genesis time
./setup_time.sh genesis.json

# Delay to let boot_enr.yaml to be created
execute_command_add_PID bootnode.log ./bootnode.sh
sleeping 3

execute_command_add_PID el_bootnode.log ./el_bootnode.sh
sleeping 3

execute_command_add_PID el_bootnode.log ./el_bootnode.sh
sleeping 1

# Start beacon nodes
BN_udp_tcp_base=9000
BN_http_port_base=8000

EL_base_network=7000
EL_base_http=6000
EL_base_auth_http=5000

(( $VC_COUNT < $TOTAL_COUNT )) && SAS=-s || SAS=

# Not sure if geth needs to have the fork epoch not configured for the stale nodes.
# I'm assuming no, so all ELs are started with the epocks set.
# (that is, before resetting the genesis.json file fork times a little further down
# this file.)
for (( el=1; el<=$TOTAL_COUNT; el++ )); do
    execute_command_add_PID geth_$el.log ./geth.sh $DATADIR/geth_datadir$el $((EL_base_network + $el)) $((EL_base_http + $el)) $((EL_base_auth_http + $el)) $genesis_file
done

sleeping 20

# Reset the `genesis.json` config file fork times.
sed -i 's/"shanghaiTime".*$/"shanghaiTime": 0,/g' $genesis_file
sed -i 's/"cancunTime".*$/"cancunTime": 0,/g' $genesis_file

# Start beacon nodes. Which:
# - Are running the ligthouse version that is being tested.
# - Have the fork epoch set for the capella and deneb hardforks.
for (( bn=1; bn<=$BN_COUNT; bn++ )); do
    secret=$DATADIR/geth_datadir$bn/geth/jwtsecret
    echo $secret
    execute_command_add_PID beacon_node_$bn.log ./beacon_node.sh $SAS -d $DEBUG_LEVEL $DATADIR/node_$bn $((BN_udp_tcp_base + $bn)) $((BN_udp_tcp_base + $bn + 100)) $((BN_http_port_base + $bn)) http://localhost:$((EL_base_auth_http + $bn)) $secret
done

# Start stale nodes.
# I haven't messed witht the fork epochs. Right now the stale nodes start on the
# previous released version then get updated to the code being tested.
# Log files are named beacon_node_stale_* to avoid them being overwritten after
# restart.
for (( bn=$BN_COUNT+1; bn<=$TOTAL_COUNT; bn++ )); do
    secret=$DATADIR/geth_datadir$bn/geth/jwtsecret
    echo $secret
    execute_command_add_PID_STALE beacon_node_stale_$bn.log ./beacon_node.sh -b lighthouse_prev $SAS -d $DEBUG_LEVEL $DATADIR/node_$bn $((BN_udp_tcp_base + $bn)) $((BN_udp_tcp_base + $bn + 100)) $((BN_http_port_base + $bn)) http://localhost:$((EL_base_auth_http + $bn)) $secret
done

# Start requested number of validator clients.
# Validators are assigned to all non-stale nodes before being assigned to
# stale nodes. So, if you want validators on stale nodes, you'll need
# VC_COUNT > BN_COUNT
for (( vc=1; vc<=$VC_COUNT; vc++ )); do
    if [ $vc -le $BN_COUNT ]; then
      execute_command_add_PID validator_node_$vc.log ./validator_client.sh $BUILDER_PROPOSALS -d $DEBUG_LEVEL $DATADIR/node_$vc http://localhost:$((BN_http_port_base + vc))
    else
      execute_command_add_PID_STALE validator_node_$vc.log ./validator_client.sh $BUILDER_PROPOSALS -d $DEBUG_LEVEL $DATADIR/node_$vc http://localhost:$((BN_http_port_base + vc))
    fi
done

echo "Started!"

