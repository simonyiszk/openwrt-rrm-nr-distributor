#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -e
BASE_DIR=$(cd -- "$(dirname "$0")/../.." && pwd)
. "$(dirname "$0")/../env.common"
echo "[skip] Using LOG_FILE=$LOG_FILE" >&2
SCENARIO="$SCENARIO_DIR/skip" load_scenario || exit 1
export SCENARIO
BIN="$BASE_DIR/bin/rrm_nr"
STATE_FILE="/tmp/rrm_nr_runtime"
# Clean prior state so assertions only look at this run
rm -f "$STATE_DIR/rrm_nr_set.log" "$STATE_DIR"/*.current 2>/dev/null || true
RRM_NR_UPDATE_INTERVAL=1 RRM_NR_JITTER_MAX=0 RRM_NR_DEBUG=1 RRM_NR_SKIP_IFACES="wlan1" RRM_NR_MAX_CYCLES=3 \
  /bin/sh "$BIN" > /dev/null 2>&1 &
PID=$!
wait $PID 2>/dev/null || true
# rrm_nr_set log should only contain wlan0 entries
if grep -q '^wlan1 ' "$STATE_DIR/rrm_nr_set.log" 2>/dev/null; then
  echo "Skip scenario failure: wlan1 should have been skipped" >&2
  exit 1
fi
if ! grep -q '^wlan0 ' "$STATE_DIR/rrm_nr_set.log" 2>/dev/null; then
  echo "Skip scenario failure: wlan0 update missing" >&2
  exit 1
fi
echo "Scenario skip: PASS"
