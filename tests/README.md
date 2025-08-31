Test Harness for rrm_nr
=======================

Lightweight POSIX shell harness to exercise core logic of `bin/rrm_nr` without a full OpenWrt runtime.

Concepts:
- Provide mock `ubus`, `jsonfilter`, `iwinfo`, `logger` in PATH ahead of system ones.
- Feed deterministic data sets for hostapd objects, neighbor reports, and mDNS browse output.
- Capture daemon stdout/stderr and resulting state files to assert behavior.

Structure:
```
/tests
  README.md
  run-tests.sh                # entrypoint: runs scenario_basic, scenario_skip, scenario_reload
  env.common                  # shared helpers / PATH overrides
  mocks/
    ubus                      # mock ubus dispatcher (list/call subset)
    jsonfilter                # minimal jsonfilter extractor
    iwinfo                    # returns ESSID for iface
    logger                    # capture logs to file (timestamp prefixed)
    uci                       # minimal get/show/-q support for reload scenario
    md5sum                    # optional pass-through / fallback
  scenarios/
    basic/                    # two ifaces, normal operation
    skip/                     # skip list (wlan1 skipped)
    reload/                   # exercise SIGHUP reload timing changes
  scripts/
    scenario_basic.sh
    scenario_skip.sh
    scenario_reload.sh
    test_install.sh           # separate installer behavior test (not in run-tests.sh)
  state/                      # ephemeral runtime artifacts (cleared per run)
```

Running core daemon scenarios:
```
cd tests
./run-tests.sh
```

Running installer test (validates dependency detection, wireless warnings & auto-fix, persistence entries):
```
sh tests/scripts/test_install.sh
```

Each scenario sets variables / creates fixture files consumed by mocks.

Notes:
- Subset of ubus methods implemented (list, call hostapd.X rrm_nr_get_own, bss, rrm_nr_list/set, umdns browse/update).
- Environment variables used by tests: `RRM_NR_UPDATE_INTERVAL`, `RRM_NR_JITTER_MAX`, `RRM_NR_DEBUG`, `RRM_NR_MAX_CYCLES`, `RRM_NR_SKIP_IFACES`, `RRM_NR_UMDNS_REFRESH_INTERVAL`.
- Reload scenario injects a mock UCI file (`state/uci.conf`) and sends SIGHUP to daemon.
- Installer test sets `RRM_NR_TEST_MODE=1` to validate wireless config inside a staged prefix.
- Hashing via real md5sum if available; fallback script provides deterministic stub hash.
