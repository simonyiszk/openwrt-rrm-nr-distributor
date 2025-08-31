#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Common helpers for rrm_nr init script and daemon.

# normalize_iflist <list>
#   Converts commas/tabs to spaces, collapses whitespace, de-duplicates, outputs space-separated list.
normalize_iflist() {
	lst="$1"
	[ -z "$lst" ] && return 0
	lst=$(printf '%s' "$lst" | tr ',\t' '  ' | tr -s ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')
	lst=${lst# }
	printf '%s' "$lst"
}

# rrm_get_own_quick <iface>
#   Adaptive retry (200ms steps up to 1s) for transient ubus rc=4 (NOT_FOUND) when calling hostapd rrm_nr_get_own.
#   Falls back to single 1s wait if no high-resolution usleep present.
if [ -z "$_RRM_NR_FRACTIONAL_SLEEP_INIT" ]; then
	_RRM_NR_FRACTIONAL_SLEEP_INIT=1
	RRM_NR_HAS_USLEEP=0; command -v usleep >/dev/null 2>&1 && RRM_NR_HAS_USLEEP=1
	RRM_NR_HAS_FRAC_SLEEP=0
	# Detect if 'sleep' supports fractional seconds (best-effort, requires date ms support)
	if [ "$RRM_NR_HAS_USLEEP" -eq 0 ]; then
		ts_a=$(date +%s%3N 2>/dev/null)
		sleep 0.1 2>/dev/null && ts_b=$(date +%s%3N 2>/dev/null)
		if echo "$ts_a$ts_b" | grep -qE '^[0-9]+$' && [ -n "$ts_a" ] && [ -n "$ts_b" ]; then
			delta=$((ts_b - ts_a))
			# Expect ~100ms (<900ms) if fractional supported
			[ "$delta" -gt 0 ] && [ "$delta" -lt 900 ] && RRM_NR_HAS_FRAC_SLEEP=1
		else
			# If we cannot measure (no %3N), heuristically assume fractional if no error emitted
			# but silence errors already; remain 0 (integer only)
			:
		fi
	fi
fi

# rrm_nr_sleep_ms <milliseconds>
rrm_nr_sleep_ms() {
	ms=$1; [ -z "$ms" ] && return 0
	if [ "$ms" -le 0 ]; then return 0; fi
	if [ "$RRM_NR_HAS_USLEEP" -eq 1 ]; then
		usleep $((ms * 1000))
		return 0
	fi
	if [ "$RRM_NR_HAS_FRAC_SLEEP" -eq 1 ]; then
		# Format as seconds with 3 decimal places (ms guaranteed <= 1000 in our usage)
		sec_int=$((ms / 1000))
		ms_rem=$((ms % 1000))
		if [ "$sec_int" -gt 0 ]; then
			sleep "$sec_int"
		fi
		if [ "$ms_rem" -gt 0 ]; then
			# Compose fractional part: ensure leading zeros for ms_rem <100
			frac=$(printf '%03d' "$ms_rem")
			sleep "0.$frac" 2>/dev/null || sleep 1
		fi
		return 0
	fi
	# Fallback: integer sleep (round up any partial ms to 1s)
	sleep 1
}


rrm_get_own_quick() {
	iface="$1"
	# Allow override (bounded) for slower environments via env RRM_NR_QUICK_MAX_MS (cap 5000)
	max_ms=${RRM_NR_QUICK_MAX_MS:-2000}
	# Basic numeric validation
	case "$max_ms" in ''|*[!0-9]* ) max_ms=2000;; esac
	[ "$max_ms" -gt 5000 ] && max_ms=5000
	interval_ms=200; elapsed=0; rc=0; out=""
	while [ "$elapsed" -le "$max_ms" ]; do
		out=$(ubus call "hostapd.$iface" rrm_nr_get_own 2>/dev/null); rc=$?
		if [ "$rc" -eq 0 ]; then
			printf '%s' "$out"
			return 0
		fi
		[ "$rc" -ne 4 ] && return 1
		rrm_nr_sleep_ms "$interval_ms"
		if [ "$RRM_NR_HAS_USLEEP" -eq 1 ] || [ "$RRM_NR_HAS_FRAC_SLEEP" -eq 1 ]; then
			elapsed=$((elapsed + interval_ms))
		else
			elapsed=$((elapsed + 1000))
		fi
	done
	return 1
}

## rrm_nr_map_ifaces
# Outputs aligned columns: iface bssid chan freq_mhz ssid
rrm_nr_map_ifaces() {
	# Cache iw dev output once (channel/freq per underlying interface, keyed by MAC addr)
	if [ -z "$_RRM_NR_IW_DEV_CACHE" ]; then
		_RRM_NR_IW_DEV_CACHE=$(iw dev 2>/dev/null)
	fi
	for obj in $(ubus list hostapd.* 2>/dev/null); do
		ifc=${obj#hostapd.}
		ssid=""; bssid=""; chan=""; freq_mhz=""; ifname=""; width_mhz=""; center1_mhz=""
		for method in rrm_nr_get_own get_config bss; do
			[ -n "$ssid" ] && [ -n "$bssid" ] && [ -n "$chan" ] && [ -n "$freq_mhz" ] && break
			json=$(ubus call "$obj" "$method" 2>/dev/null || true) || json=""
			[ -z "$json" ] && continue
			# BSSID / SSID
			[ -z "$bssid" ] && bssid=$(echo "$json" | jsonfilter -e '@.bssid' 2>/dev/null)
			[ -z "$bssid" ] && bssid=$(echo "$json" | jsonfilter -e '@.bss[0].bssid' 2>/dev/null)
			ssid=$(echo "$json" | jsonfilter -e '@.ssid' 2>/dev/null)
			[ -z "$ssid" ] && ssid=$(echo "$json" | jsonfilter -e '@.bss[0].ssid' 2>/dev/null)
			if [ -z "$ssid" ] && [ "$method" = "rrm_nr_get_own" ]; then
				ssid=$(echo "$json" | jsonfilter -e '@.value[1]' 2>/dev/null)
				[ -z "$bssid" ] && bssid=$(echo "$json" | jsonfilter -e '@.value[0]' 2>/dev/null)
			fi
			# Underlying netdev (varies by build: iface / ifname)
			[ -z "$ifname" ] && ifname=$(echo "$json" | jsonfilter -e '@.iface' 2>/dev/null)
			[ -z "$ifname" ] && ifname=$(echo "$json" | jsonfilter -e '@.ifname' 2>/dev/null)
			# Channel / Frequency
			[ -z "$chan" ] && chan=$(echo "$json" | jsonfilter -e '@.channel' 2>/dev/null)
			[ -z "$chan" ] && chan=$(echo "$json" | jsonfilter -e '@.bss[0].channel' 2>/dev/null)
			[ -z "$freq_mhz" ] && freq_mhz=$(echo "$json" | jsonfilter -e '@.freq' 2>/dev/null)
			[ -z "$freq_mhz" ] && freq_mhz=$(echo "$json" | jsonfilter -e '@.frequency' 2>/dev/null)
			# Numeric SSID array form
			if [ -z "$ssid" ] && echo "$json" | grep -q '"ssid" *:' && echo "$json" | grep -q '\['; then
				arr=$(echo "$json" | sed -n 's/.*"ssid" *: *\[\([^]]*\)\].*/\1/p' | tr -d '"')
				if echo "$arr" | grep -qE '^[0-9][0-9, ]*$'; then
					ssid=$(echo "$arr" | tr ',' ' ' | awk '{for(i=1;i<=NF;i++){ if($i!="") printf "%c", $i }}')
				fi
			fi
			# Hex SSID fallback
			if [ -z "$ssid" ]; then
				hex=$(echo "$json" | sed -n 's/.*"ssid" *: *"\([0-9A-Fa-f]\{2,\}\)".*/\1/p')
				if [ -n "$hex" ] && echo "$hex" | grep -qE '^[0-9A-Fa-f]+$'; then
					ssid=$(echo "$hex" | sed 's/../& /g' | awk '{for(i=1;i<=NF;i++){ c=strtonum("0x"$i); if(c>=32 && c<=126) printf "%c", c; else printf "?" }}')
				fi
			fi
		done
		# Deterministic channel/freq via iw dev (match BSSID, first channel line after address)
		if { [ -z "$chan" ] || [ -z "$freq_mhz" ] || [ -z "$width_mhz" ] || [ -z "$center1_mhz" ]; } && [ -n "$bssid" ] && [ "$bssid" != "(unknown)" ]; then
			bsl=$(echo "$bssid" | tr 'A-F' 'a-f')
			line=$(printf '%s\n' "$_RRM_NR_IW_DEV_CACHE" | awk -v mac="$bsl" 'BEGIN{IGNORECASE=1} tolower($0) ~ /addr/ && tolower($0) ~ mac {found=1; next} found && /channel [0-9]+/ {print; exit}')
			if [ -n "$line" ]; then
				[ -z "$chan" ] && chan=$(echo "$line" | sed -n 's/.*channel \([0-9][0-9]*\).*/\1/p')
				[ -z "$freq_mhz" ] && freq_mhz=$(echo "$line" | sed -n 's/.*(\([0-9][0-9]*\) MHz).*/\1/p')
				[ -z "$width_mhz" ] && width_mhz=$(echo "$line" | sed -n 's/.*width: *\([0-9][0-9]*\) *MHz.*/\1/p')
				[ -z "$center1_mhz" ] && center1_mhz=$(echo "$line" | sed -n 's/.*center1: *\([0-9][0-9]*\) *MHz.*/\1/p')
			fi
		fi
		[ -z "$ssid" ] && ssid="(unknown)"
		[ -z "$bssid" ] && bssid="(unknown)"
		[ -z "$chan" ] && chan="-"
		[ -z "$freq_mhz" ] && freq_mhz="-"
		[ -z "$width_mhz" ] && width_mhz="-"
		[ -z "$center1_mhz" ] && center1_mhz="-"
		printf '%-12s %-17s %-4s %-6s %-5s %-6s %s\n' "$ifc" "$bssid" "$chan" "$freq_mhz" "$width_mhz" "$center1_mhz" "$ssid"
	done
}

# JSON variant: outputs array of objects with keys
rrm_nr_map_ifaces_json() {
	if [ -z "$_RRM_NR_IW_DEV_CACHE" ]; then
		_RRM_NR_IW_DEV_CACHE=$(iw dev 2>/dev/null)
	fi
	printf '['
	first=1
	for obj in $(ubus list hostapd.* 2>/dev/null); do
		ifc=${obj#hostapd.}
		ssid=""; bssid=""; chan=""; freq_mhz=""; ifname=""; width_mhz=""; center1_mhz=""
		for method in rrm_nr_get_own get_config bss; do
			[ -n "$ssid" ] && [ -n "$bssid" ] && [ -n "$chan" ] && [ -n "$freq_mhz" ] && [ -n "$width_mhz" ] && [ -n "$center1_mhz" ] && break
			json=$(ubus call "$obj" "$method" 2>/dev/null || true) || json=""
			[ -z "$json" ] && continue
			[ -z "$bssid" ] && bssid=$(echo "$json" | jsonfilter -e '@.bssid' 2>/dev/null)
			[ -z "$bssid" ] && bssid=$(echo "$json" | jsonfilter -e '@.bss[0].bssid' 2>/dev/null)
			ssid=$(echo "$json" | jsonfilter -e '@.ssid' 2>/dev/null)
			[ -z "$ssid" ] && ssid=$(echo "$json" | jsonfilter -e '@.bss[0].ssid' 2>/dev/null)
			if [ -z "$ssid" ] && [ "$method" = "rrm_nr_get_own" ]; then
				ssid=$(echo "$json" | jsonfilter -e '@.value[1]' 2>/dev/null)
				[ -z "$bssid" ] && bssid=$(echo "$json" | jsonfilter -e '@.value[0]' 2>/dev/null)
			fi
			[ -z "$ifname" ] && ifname=$(echo "$json" | jsonfilter -e '@.iface' 2>/dev/null)
			[ -z "$ifname" ] && ifname=$(echo "$json" | jsonfilter -e '@.ifname' 2>/dev/null)
			[ -z "$chan" ] && chan=$(echo "$json" | jsonfilter -e '@.channel' 2>/dev/null)
			[ -z "$chan" ] && chan=$(echo "$json" | jsonfilter -e '@.bss[0].channel' 2>/dev/null)
			[ -z "$freq_mhz" ] && freq_mhz=$(echo "$json" | jsonfilter -e '@.freq' 2>/dev/null)
			[ -z "$freq_mhz" ] && freq_mhz=$(echo "$json" | jsonfilter -e '@.frequency' 2>/dev/null)
			if [ -z "$ssid" ] && echo "$json" | grep -q '"ssid" *:' && echo "$json" | grep -q '\['; then
				arr=$(echo "$json" | sed -n 's/.*"ssid" *: *\[\([^]]*\)\].*/\1/p' | tr -d '"')
				if echo "$arr" | grep -qE '^[0-9][0-9, ]*$'; then
					ssid=$(echo "$arr" | tr ',' ' ' | awk '{for(i=1;i<=NF;i++){ if($i!="") printf "%c", $i }}')
				fi
			fi
			if [ -z "$ssid" ]; then
				hex=$(echo "$json" | sed -n 's/.*"ssid" *: *"\([0-9A-Fa-f]\{2,\}\)".*/\1/p')
				if [ -n "$hex" ] && echo "$hex" | grep -qE '^[0-9A-Fa-f]+$'; then
					ssid=$(echo "$hex" | sed 's/../& /g' | awk '{for(i=1;i<=NF;i++){ c=strtonum("0x"$i); if(c>=32 && c<=126) printf "%c", c; else printf "?" }}')
				fi
			fi
			if { [ -z "$chan" ] || [ -z "$freq_mhz" ] || [ -z "$width_mhz" ] || [ -z "$center1_mhz" ]; } && [ -n "$bssid" ] && [ "$bssid" != "(unknown)" ]; then
				bsl=$(echo "$bssid" | tr 'A-F' 'a-f')
				line=$(printf '%s\n' "$_RRM_NR_IW_DEV_CACHE" | awk -v mac="$bsl" 'BEGIN{IGNORECASE=1} tolower($0) ~ /addr/ && tolower($0) ~ mac {found=1; next} found && /channel [0-9]+/ {print; exit}')
				if [ -n "$line" ]; then
					[ -z "$chan" ] && chan=$(echo "$line" | sed -n 's/.*channel \([0-9][0-9]*\).*/\1/p')
					[ -z "$freq_mhz" ] && freq_mhz=$(echo "$line" | sed -n 's/.*(\([0-9][0-9]*\) MHz).*/\1/p')
					[ -z "$width_mhz" ] && width_mhz=$(echo "$line" | sed -n 's/.*width: *\([0-9][0-9]*\) *MHz.*/\1/p')
					[ -z "$center1_mhz" ] && center1_mhz=$(echo "$line" | sed -n 's/.*center1: *\([0-9][0-9]*\) *MHz.*/\1/p')
				fi
			fi
		done
		[ -z "$ssid" ] && ssid="(unknown)"
		[ -z "$bssid" ] && bssid="(unknown)"
		[ -z "$chan" ] && chan="-"
		[ -z "$freq_mhz" ] && freq_mhz="-"
		[ -z "$width_mhz" ] && width_mhz="-"
		[ -z "$center1_mhz" ] && center1_mhz="-"
		# Emit JSON object (escape quotes in ssid)
		ssid_esc=$(printf '%s' "$ssid" | sed 's/\\/\\\\/g; s/"/\\"/g')
		[ $first -eq 0 ] && printf ','
		first=0
		printf '\n{"iface":"%s","bssid":"%s","channel":"%s","freq_mhz":"%s","width_mhz":"%s","center1_mhz":"%s","ssid":"%s"}' "$ifc" "$bssid" "$chan" "$freq_mhz" "$width_mhz" "$center1_mhz" "$ssid_esc"
	done
	printf '\n]\n'
}

# rrm_nr_probe_iface <iface>
#   Attempts quick readiness probe; prints ms + attempts (key=value) or error rc.
rrm_nr_probe_iface() {
	ifc="$1"; [ -z "$ifc" ] && return 1
	max_ms=${RRM_NR_QUICK_MAX_MS:-2000}
	case "$max_ms" in ''|*[!0-9]* ) max_ms=2000;; esac
	[ "$max_ms" -gt 5000 ] && max_ms=5000
	start=$(date +%s%3N 2>/dev/null); elapsed=0; interval=200; attempts=0; rc=1
	while [ "$elapsed" -le "$max_ms" ]; do
		attempts=$((attempts+1))
		ubus call "hostapd.$ifc" rrm_nr_get_own >/dev/null 2>&1; rc=$?
		[ "$rc" -eq 0 ] && break
		[ "$rc" -ne 4 ] && break
		rrm_nr_sleep_ms "$interval"
		if [ "$RRM_NR_HAS_USLEEP" -eq 1 ] || [ "$RRM_NR_HAS_FRAC_SLEEP" -eq 1 ]; then
			elapsed=$((elapsed + interval))
		else
			elapsed=$((elapsed + 1000))
		fi
	done
	end=$(date +%s%3N 2>/dev/null)
	[ -n "$start" ] && [ -n "$end" ] && ms=$((end-start)) || ms=-1
	printf 'iface=%s rc=%s attempts=%s ms=%s max_ms=%s\n' "$ifc" "$rc" "$attempts" "$ms" "$max_ms"
}

# rrm_nr_classify_ifaces <skip_list>
#   Iterates hostapd objects; outputs three space-separated lists via stdout in form:
#     cfg_skipped="..." not_ready="..." ready_count=N
#   (Lists may be empty strings). Intended for summary logging.
rrm_nr_classify_ifaces() {
	skip_list="$1"
	cfg_skipped=""; not_ready=""; ready_count=0
	for obj in $(ubus list hostapd.* 2>/dev/null); do
		iface=${obj#hostapd.}
		# config skip
		sk=0; for s in $skip_list; do [ "$iface" = "$s" ] && sk=1 && break; done
		if [ $sk -eq 1 ]; then
			cfg_skipped="$cfg_skipped $iface"
			continue
		fi
		json=$(ubus call "$obj" rrm_nr_get_own 2>/dev/null || true)
		[ -n "$json" ] && val=$(echo "$json" | jsonfilter -e '$.value') || val=""
		if [ -n "$val" ]; then
			ready_count=$((ready_count+1))
		else
			not_ready="$not_ready $iface"
		fi
	done
	echo "cfg_skipped='${cfg_skipped# }' not_ready='${not_ready# }' ready_count=$ready_count"
}
