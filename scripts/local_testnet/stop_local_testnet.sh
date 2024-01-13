#!/usr/bin/env bash
# Stop all processes that were started with start_local_testnet.sh

set -Eeuo pipefail

source ./vars.env

PID_FILE=$TESTNET_DIR/PIDS.pid
PID_FILE_STALE=$TESTNET_DIR/PIDS_STALE.pid
./kill_processes.sh $PID_FILE
./kill_processes.sh $PID_FILE_STALE
rm -f $PID_FILE
rm -f $PID_FILE_STALE
