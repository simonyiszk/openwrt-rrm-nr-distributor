# Developer Guide

This document captures developer-focused details removed from the README for end-user clarity.

## Repository Layout

Path | Purpose
-----|--------
`service/rrm_nr.init` | Init script (procd) orchestrating readiness, argument assembly, admin commands.
`bin/rrm_nr` | Prebuilt daemon (opaque); consumes `SSIDn=` args and performs periodic updates.
`lib/rrm_nr_common.sh` | Shared helpers (normalization, retries, probes). Optional but preferred.
`config/rrm_nr.config` | Example UCI configuration template.
`examples/` | Example wireless config enabling required 802.11k features.
`tests/` | (If present) harness for basic functional validation.
`docs/` | Documentation (CHANGELOG, developer notes).

## Coding Guidelines

- Target shell: BusyBox ash (strict POSIX subset). Avoid arrays, `[[` tests, process substitution.
- Keep init script fast and deterministic; heavy logic belongs in daemon.
- Prefer single concise log lines. Use `logger -t rrm_nr -p daemon.info|error` and guarded debug lines when `debug=1`.
- Avoid unbounded loops; timeouts must be explicit.
- Favor idempotent operations (cache directory creation, baseline push tracking).

## Versioning

- Bump `RRM_NR_INIT_VERSION` in `service/rrm_nr.init` for each tagged release.
- Maintain `docs/CHANGELOG.md` with Added/Changed/Fixed/Removed sections.

## Release Checklist

1. Ensure working branch merged (fast-forward) into main.
2. Update CHANGELOG with final date & content.
3. Bump `RRM_NR_INIT_VERSION`.
4. Run lint/tests (if available).
5. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push --tags`.
6. Build package (optional) and publish ipk.
7. Announce / update external documentation.

## Metrics Overview

Metric | Notes
-------|------
`cache_hits/misses` | Per-SSID diff detection effectiveness.
`nr_sets_sent/suppressed` | Interface-level push behavior (suppression health).
`baseline_ssids` | Distinct SSIDs receiving baseline push this process.
`remote_entries_merged` | Aggregate remote TXT line ingestion (raw).
`remote_unique_cycle/total` | Per-cycle and cumulative uniqueness of remote entries.
`nr_set_failures` | Hostapd update failures; investigate if non-zero.
`neighbor_count_<iface>` | Post self-filter neighbor set sizes.

## Admin Commands Implementation Notes

Command | Internals
--------|----------
`summary` | Parses metrics file; computes neighbor count min/max/avg.
`reset_metrics` | Sends SIGUSR2 -> daemon resets counters & uniqueness.
`refresh` | SIGUSR1 -> immediate update cycle outside normal cadence.
`diag` | Quick probe for each hostapd object using `rrm_nr_probe_iface`.

## Skip List Normalization

- Accept lines with or without `hostapd.` prefix; stored internally stripped.
- Normalization collapses duplicates and extraneous whitespace.
- Reload (SIGHUP) or startup reconstructs skip list each time.

## Remote Uniqueness Tracking

- Cycle uniqueness from `sort -u` of raw remote TXT lines.
- Cumulative uniqueness stored as normalized lines in `/tmp/rrm_nr_state/remote_seen`.
- Reset via SIGUSR2.

## Baseline Push Logic

- Each SSID hash tracked in `baseline_sent_hashes` in daemon memory.
- If no diff but baseline not yet done, force a push (ensures hostapd populated).

## Future Work Ideas

- Configurable interface-level disable (planned `option rrm_nr_disable '1'`).
- Neighbor list length cap + truncation metric.
- Optional remote ingestion toggle for isolated test nodes.
- JSON export endpoint (lightweight HTTP or ubus method) for metrics.

## Testing Tips

- Use `RRM_NR_MAX_CYCLES=3` env var (if supported) for bounded test runs.
- Add `debug=1` temporarily; remember to turn it off for performance.
- Validate mDNS via: `ubus call umdns browse | jsonfilter -e '@["_rrm_nr._udp"][*].txt[*]'`.

## Troubleshooting Flow

1. No TXT records: confirm `umdns` running; run `ubus call umdns update`.
2. Empty neighbor lists: check logs for `filter self (orig= after=...)` diagnostics.
3. `remote_unique_total` stuck: ensure remote TXT diversity; verify seen file writes.
4. High `nr_set_failures`: inspect hostapd logs (`logread -e hostapd`).

## License

GPLv2 – contributions must include compatible license headers where appropriate.
