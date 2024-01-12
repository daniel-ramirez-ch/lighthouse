#!/usr/bin/env bash
# Stop all processes on the stale pids file.

set -Eeuo pipefail

source ./vars.env

PID_FILE=$TESTNET_DIR/PIDS_STALE.pid
./kill_processes.sh $PID_FILE
rm -f $PID_FILE
