#!/usr/bin/env bash
# Starts the stale nodes with the latest lighthouse version (the code we're
# testing) and the right fork epochs configured.
# This is based on start_local_testnet.sh but the logic concerning network
# initialization (eg. setting up the genesis file) and starting the non-stale
# nodes.

set -Eeuo pipefail

source ./vars.env

# Set a higher ulimit in case we want to import 1000s of validators.
ulimit -n 65536

DEBUG_LEVEL=${DEBUG_LEVEL:-info}
BUILDER_PROPOSALS=

while getopts "ph" flag; do
  case "${flag}" in
    p) BUILDER_PROPOSALS="-p";;
    h)
    echo "Start the stale nodes with the updated lighthouse version and the"
    echo "forks epochs set."
    echo "usage: $0 <Options>"
    echo
    echo "Options:"
    echo "   -p:             enable builder proposals"
  esac
done

genesis_file=${@:$OPTIND+0:1}

# Init some constants
PID_FILE=$TESTNET_DIR/PIDS.pid
LOG_DIR=$TESTNET_DIR

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

# Start beacon nodes
BN_udp_tcp_base=9000
BN_http_port_base=8000

EL_base_network=7000
EL_base_http=6000
EL_base_auth_http=5000

sleeping 20

(( $VC_COUNT < $TOTAL_COUNT )) && SAS=-s || SAS=

# Start beacon nodes.
for (( bn=$BN_COUNT+1; bn<=$TOTAL_COUNT; bn++ )); do
    secret=$DATADIR/geth_datadir$bn/geth/jwtsecret
    echo $secret
    execute_command_add_PID beacon_node_$bn.log ./beacon_node.sh $SAS -d $DEBUG_LEVEL $DATADIR/node_$bn $((BN_udp_tcp_base + $bn)) $((BN_udp_tcp_base + $bn + 100)) $((BN_http_port_base + $bn)) http://localhost:$((EL_base_auth_http + $bn)) $secret
done

# Start validators
for (( vc=$BN_COUNT+1; vc<=$VC_COUNT; vc++ )); do
  execute_command_add_PID validator_node_$vc.log ./validator_client.sh $BUILDER_PROPOSALS -d $DEBUG_LEVEL $DATADIR/node_$vc http://localhost:$((BN_http_port_base + vc))
done

echo "Updated and started stale nodes!"

