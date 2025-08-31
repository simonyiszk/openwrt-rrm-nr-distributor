#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -e
# shellcheck disable=SC2034
SCENARIO_DIR=$(cd -- "$(dirname "$0")/.." && pwd)/scenarios
SCENARIO="$SCENARIO_DIR/basic"
. "$(dirname "$0")/../env.common"
echo "[basic] Using LOG_FILE=$LOG_FILE" >&2
echo "[basic] HARNESS_DIR=$HARNESS_DIR MOCK_DIR=$MOCK_DIR" >&2
echo "[basic] PATH=$PATH" >&2
export LOG_FILE

# Isolate previous runs
rm -f "$STATE_DIR/rrm_nr_set.log" "$STATE_DIR"/*.current 2>/dev/null || true

SCENARIO="$SCENARIO" load_scenario || exit 1
export SCENARIO

# Run daemon bounded cycles
BASE_ROOT=$(dirname "$0")/../..
BIN="$(cd -- "$BASE_ROOT" && pwd)/bin/rrm_nr"
RRM_NR_UPDATE_INTERVAL=1 RRM_NR_JITTER_MAX=0 RRM_NR_DEBUG=1 RRM_NR_TEST_FORCE_UPDATE=1 RRM_NR_MAX_CYCLES=3 \
  /bin/sh "$BIN" > /dev/null 2>&1 &
PID=$!
echo "[basic] Started daemon PID=$PID (max cycles)" >&2
wait $PID 2>/dev/null || true
echo "[basic] Daemon exited (max cycles)" >&2

# Assertions: runtime state file present, log contains update message
STATE_FILE="/tmp/rrm_nr_runtime"
[ -f "$STATE_FILE" ] || { echo "Missing runtime state file" >&2; exit 1; }

sleep 1
if [ ! -s "$STATE_DIR/rrm_nr_set.log" ]; then
  echo "[basic] DEBUG log tail:" >&2
  tail -n 100 "$LOG_FILE" >&2 || true
  echo "[basic] DEBUG state dir listing:" >&2
  ls -l "$STATE_DIR" >&2 || true
  echo "Expected rrm_nr_set.log not written" >&2
  exit 1
fi

echo "Scenario basic: PASS"
