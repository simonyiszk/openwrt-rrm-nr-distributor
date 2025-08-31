#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -e
DIR=$(cd -- "$(dirname "$0")" && pwd)
chmod +x "$DIR"/mocks/* 2>/dev/null || true
chmod +x "$DIR"/scripts/*.sh 2>/dev/null || true
export LOG_FILE="$DIR/test.log"
: > "$LOG_FILE"
STATE_DIR="$DIR/state"
rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
export STATE_DIR

# Execute scenarios
"$DIR/scripts/scenario_basic.sh"
"$DIR/scripts/scenario_skip.sh"
"$DIR/scripts/scenario_reload.sh"

echo "All scenarios: PASS"
