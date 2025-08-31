# Copilot Instructions

Purpose: Enable AI agents to make fast, safe improvements to this OpenWrt 802.11k Neighbor Report (NR) distributor.

## Architecture (Current Minimal Set + Tooling)
- `service/rrm_nr.init`: procd init script: gathers per‑iface NR JSON, assembles positional TXT args, exports env → daemon, registers mDNS service, exposes admin subcommands.
- `bin/rrm_nr`: Prebuilt daemon (opaque) consuming `SSIDn=<nrdata>` positional args; performs periodic updates & mDNS refreshes; supports signals (HUP/USR1/USR2) and metrics.
- `lib/rrm_nr_common.sh`: Shared POSIX helpers (adaptive retry, iface mapping, millisecond sleep abstraction, readiness probes, normalization).
- `scripts/install.sh`: Idempotent installer (dependencies, sysupgrade persistence of binary/init/lib, wireless validation & optional auto‑fix, configurable prefix staging, package manager detection opkg/apk).
- `package/rrm-nr-distributor/`: OpenWrt package skeleton (Makefile + default `/etc/config/rrm_nr`).
- `tests/` harness (mocks + scenarios): basic, skip, reload, plus install script test under `tests/scripts/test_install.sh`.
- `examples/wireless.config`: Example dual‑band wireless config enabling required 802.11k / BSS transition options.

## Runtime Data Flow
1. Init script counts enabled `wifi-iface` stanzas (ignores `option disabled '1'`).
2. Wait loop until `ubus list hostapd.*` matches enabled count (3s sleep cadence; max 5 min timeout).
3. Per iface quick retrieval: adaptive retry (200ms steps ≤1s total when high‑res sleep available; otherwise integer sleep fallback) via `rrm_get_own_quick` calling `ubus rrm_nr_get_own`.
4. Assemble concatenated string `+SSID<n>=<value>` (delimiter `+` guaranteed not in SSIDs); remove leading `+`; split to positional args.
5. Launch daemon with those args, exporting timing + control env vars; register mDNS TXT records via procd/umdns.
6. Daemon cycles: rebuild neighbor lists, optionally refresh mDNS (rate‑limited), update metrics/state files.
7. Signals: HUP triggers UCI reload (init triggers SIGHUP; daemon re‑reads env/uci), USR1 immediate refresh, USR2 metrics reset (internal).

## Key Conventions
- Delimiter: `+` (invalid in SSIDs); never transform SSID contents.
- Positional ordering: Append only `SSIDn=` sequentially; never renumber earlier entries (consumer stability).
- Error strategy: Hard fail (exit) for structural issues (no wireless config, zero enabled ifaces, timeout waiting for hostapd objects). Ubus rc=4 during initial fetch handled with bounded adaptive retry (no longer restarts wpad).
- Shell style: Strict POSIX BusyBox ash; avoid arrays, `[[ ... ]]`, process substitution, bashisms.
- Skip list: `list skip_iface '<iface>'` UCI entries (one per interface) plus future possible per‑iface disable flag (not yet implemented) — keep skip logic mirrored in counting & enumeration.
- Version: `RRM_NR_INIT_VERSION` constant in init script (bump on release tagging).
- Metrics/state: `/tmp/rrm_nr_runtime` (effective params / cycle info), `/tmp/rrm_nr_metrics` (counters); treat as ephemeral.
- Signals: HUP (reload UCI), USR1 (forced refresh), USR2 (metrics reset).

## Extending Safely
- Per‑interface disable (future): Add `option rrm_nr_disable '1'`; ensure both counting loop and per‑iface enumeration skip those if set.
- Additional TXT features: Append `+FEATURE=value` after all `SSIDn=` arguments (maintain ordering invariants so existing parsers continue to see SSID entries first).
- Retry expansion: For non‑4 failures consider at most a small fixed retry count (≤3) with single log line per iface.
- Caching / performance: If adding heavier processing, isolate to daemon not init script (init must stay fast & deterministic).
- Config growth: Any new UCI option must be documented (README + this file) with a one‑line purpose; ensure reload semantics (HUP) if runtime‑mutable.
- Packaging: Keep package Makefile install list minimal; avoid adding large dependencies unless strictly required.

## Developer Workflow
- Quick install: `sh scripts/install.sh` (adds files, optional deps, can auto‑fix wireless 802.11k/v with `--fix-wireless`).
- Manual deploy (fallback): copy init script, binary, library; enable & start service.
- Package build: Copy `package/rrm-nr-distributor` into OpenWrt buildroot `package/`, select in `menuconfig`, compile.
- Debug startup: `sh -x /etc/init.d/rrm_nr start` (verify hostapd object count + SSID arg assembly).
- mDNS validation: `ubus call umdns browse | grep SSID1=`.
- Reload after UCI edits: `/etc/init.d/rrm_nr reload` (SIGHUP path).
- Tests (functional): `tests/run-tests.sh`; installer: `tests/scripts/test_install.sh`.
- Shell lint (optional): `scripts/shellcheck.sh`.

## Observability
- Logging: `logger -t rrm_nr -p daemon.info|error` (and debug when enabled). Keep single concise line per condition.
- Runtime state: `/tmp/rrm_nr_runtime` (effective intervals, jitter cap, skip list summary).
- Metrics: `/tmp/rrm_nr_metrics` (counters: cycles, updates, cache hits/misses, etc.).
- Additional metrics (post refactor additions): `baseline_ssids` (distinct SSIDs baseline-pushed), `suppression_ratio_pct` (integer percent of per-interface updates suppressed = suppressed / (sent+suppressed) * 100). High suppression ratio after initial cycles indicates stable neighbor lists.
- Remote uniqueness metrics: `remote_unique_cycle` (distinct remote TXT entries this cycle), `remote_unique_total` (cumulative distinct remote TXT entries since process start).
- Admin subcommands (init script invoke as service actions): `mapping`, `neighbors`, `cache`, `refresh`, `diag`, `metrics`, `timing_check|timing-check`, `version`.
- Readiness probes: `diag` / `timing_check` use `rrm_nr_probe_iface` (adaptive measurement, ms+attempts).
- mDNS TXT inspection: `ubus call umdns browse | jsonfilter -e '@["_rrm_nr._udp"][*].txt[*]'`.

## Pitfalls / Edge Cases
- Hostapd object count mismatch: loop persists (3s cadence) until match or timeout (5 min). Large (>20) AP sets: measure before shortening cadence.
- Fractional sleep absence: Falls back to integer 1s sleep; adaptive retry still bounded (≤1s or single 1s wait). Optional dependency improves readiness speed (`coreutils-sleep` or busybox w/ usleep).
- Wireless missing 802.11k/BSS Transition: Installer warns; `--fix-wireless` can auto‑insert (adds tagged comment + backup `.rrm_nr.bak`).
- SSID delimiter safety: `+` must remain reserved; never sanitize away.
- UCI config persistence: `/etc/config/rrm_nr` auto‑preserved by sysupgrade (no manual entry required).
- Prebuilt binary: No source presently; any behavioral refactor limited to init + shell helpers unless binary replaced.

## UCI Options (global section quick reference)
| Option | Purpose | Notes |
|--------|---------|-------|
| enabled | Master enable (0 = skip start) | Checked only at start |
| update_interval | Base seconds between cycles | Min 5 enforced in daemon |
| jitter_max | Random 0..jitter added to each cycle | Capped ≤ half interval |
| debug | Verbose logging | Enables extra debug lines |
| umdns_refresh_interval | Min seconds between mDNS refresh pushes | Rate limit |
| umdns_settle_delay | Sleep seconds after a refresh | 0 default |
| skip_iface | List entries (one per iface) to exclude | Applied at assembly |

## Installer Flags (scripts/install.sh)
- `--add-sysupgrade`: add binary/init/lib to `/etc/sysupgrade.conf` (config already auto‑preserved).
- `--deps-auto-yes|--deps-auto-no`: non‑interactive dependency handling (required: umdns jsonfilter iwinfo; optional: coreutils-sleep/coreutils).
- `--install-optional`: install optional micro‑sleep provider.
- `--fix-wireless`: auto add missing `ieee80211k '1'` / `bss_transition '1'` to active `wifi-iface` stanzas.
- `--force-config`: overwrite existing `/etc/config/rrm_nr` with default template.
- `--no-start`: stage files only.
- `--prefix <dir>`: install into alternate root (image build staging, tests).

## Licensing
- GPLv2 (see `LICENSE`). New source files must include GPLv2 header.

## Agent Change Guidelines
- Keep init script lightweight; avoid complex loops or unbounded retries.
- When adding UCI keys: update README + this file (UCI table + brief purpose) and ensure reload logic (SIGHUP) includes them.
- Maintain delimiter / ordering invariants; run test harness after modifications.
- Provide concrete shell snippets for user‑facing changes (installer usage, service commands).
- Update version constant (`RRM_NR_INIT_VERSION`) on beta / release tagging.

End of file.