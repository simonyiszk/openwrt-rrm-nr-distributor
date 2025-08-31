#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Run shellcheck on project shell scripts (if available).
# Usage: scripts/shellcheck.sh [--fix]
# Requires: shellcheck in PATH. Safe to run locally; CI optional.

set -eu

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

# Collect scripts (exclude binary dir contents except scripts)
SCRIPTS="service/rrm_nr.init bin/rrm_nr lib/rrm_nr_common.sh tests/mocks/ubus tests/mocks/uci tests/scripts/scenario_basic.sh tests/scripts/scenario_skip.sh tests/scripts/scenario_reload.sh tests/run-tests.sh"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found in PATH; skipping lint." >&2
  exit 0
fi

FAIL=0
for f in $SCRIPTS; do
  [ -f "$f" ] || continue
  # SC1090 dynamic sourced files are intentional in tests; disable.
  if [ $FIX -eq 1 ]; then
    shellcheck -x -e SC1090 "$f" || FAIL=1
  else
    shellcheck -x -e SC1090 "$f" || FAIL=1
  fi
done

if [ $FAIL -ne 0 ]; then
  echo "Shellcheck reported issues." >&2
  exit 1
fi

echo "Shellcheck: PASS"
