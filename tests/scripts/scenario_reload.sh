#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -e
BASE_DIR=$(cd -- "$(dirname "$0")/../.." && pwd)
. "$(dirname "$0")/../env.common"
echo "[reload] Using LOG_FILE=$LOG_FILE" >&2
SCENARIO="$SCENARIO_DIR/reload" load_scenario || exit 1
export SCENARIO
BIN="$BASE_DIR/bin/rrm_nr"
STATE_FILE="/tmp/rrm_nr_runtime"
# Reset prior state
rm -f "$STATE_DIR/rrm_nr_set.log" "$STATE_DIR"/*.current 2>/dev/null || true
RRM_NR_UPDATE_INTERVAL=4 RRM_NR_JITTER_MAX=0 RRM_NR_DEBUG=1 RRM_NR_UMDNS_REFRESH_INTERVAL=2 RRM_NR_MAX_CYCLES=6 \
  /bin/sh "$BIN" > /dev/null 2>&1 &
PID=$!
# Allow initial cycle (interval 4s, but first cycle happens immediately)
sleep 1
cat > "$STATE_DIR/uci.conf" <<EOF
rrm_nr.global.update_interval=1
rrm_nr.global.jitter_max=0
rrm_nr.global.umdns_refresh_interval=1
EOF
ts_hup=$(date +%s)
kill -HUP $PID 2>/dev/null || true
# Wait remaining cycles to complete (max cycles 6)
wait $PID 2>/dev/null || true
grep -q 'Reload (SIGHUP)' "$LOG_FILE" || { echo "Reload log missing" >&2; exit 1; }
updates_after=$(awk -v t=$ts_hup '$1 ~ /^[0-9]+$/ { if($1>=t && /updated list=/) c++ } END{print c+0}' "$LOG_FILE")
[ "$updates_after" -ge 1 ] || { echo "Expected at least one update after reload" >&2; exit 1; }
echo "Scenario reload: PASS"
