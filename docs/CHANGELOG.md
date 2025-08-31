# Changelog

All notable changes will be documented here. Dates use UTC.

## [2.0.0-beta] - 2025-08-30
### Added
- Deterministic neighbor list ordering (SSID then BSSID) with duplicate suppression across remote sources.
- Per-interface neighbor count metrics (`neighbor_count_<iface>`).
- Remote uniqueness metrics: `remote_unique_cycle`, `remote_unique_total`.
- Baseline per-SSID push logic ensuring initial hostapd population even if no diff.
- `summary` one-line health command.
- `reset_metrics` command (SIGUSR2) to clear counters & uniqueness state.
- `umdns_settle_delay` config option.
- Advanced readiness tuning options (`quick_max_ms`, `second_pass_ms`).
- `nr_set_failures` metric.
- Enhanced README with commands table, security/scope, versioning guidance.

### Changed
- Replaced earlier candidate joining approach with awk-based join to remove `paste` dependency.
- Improved canonicalization and normalization of neighbor entries.
- More robust skip list normalization (accepts optional `hostapd.` prefix).

### Fixed
- Initial neighbor lists not populating (added per-SSID baseline push and instrumentation around `rrm_nr_set`).
- `remote_unique_total` counter now tracks cumulative distinct remote entries correctly.

### Removed
- Implicit dependency on `paste` for list assembly.

---

## [1.x] - Pre-refactor
Initial functional release (basic init script, daemon argument passing, mDNS registration, minimal metrics). Detailed history not backfilled.

---

## Unreleased
- Potential future: configurable list length cap & truncation metric.
- Potential future: optional remote ingestion disable flag.
