#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Basic test harness for install.sh (runs locally on a development machine, not OpenWrt itself)
# Simulates minimal OpenWrt-like filesystem tree in a temp dir.
# Focus areas:
#   1. Config creation and --force-config behavior
#   2. sysupgrade persistence additions
#   3. Wireless 802.11k/v warnings (test mode)
#   4. Prefix staging without starting service
#   5. Dependency handling logic (dry: fake opkg/apk detection)
#
# NOTE: This is a lightweight sanity test; it does not execute real opkg/apk installs.
# It injects dummy executables earlier in PATH to simulate their presence.

set -eu

ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t rrmtest)
echo "[test] root=$ROOT"
mkdir -p "$ROOT/etc/config" "$ROOT/etc/init.d" "$ROOT/usr/bin" "$ROOT/lib" "$ROOT/etc"

# Dummy wireless with one iface missing ieee80211k and another complete
cat >"$ROOT/etc/config/wireless" <<'EOF'
config wifi-iface 'default_radio0'
  option device 'radio0'
  option network 'lan'
  option mode 'ap'
  option ssid 'TestNet'
  option encryption 'psk2'
  option bss_transition '1'

config wifi-iface 'default_radio1'
  option device 'radio1'
  option network 'lan'
  option mode 'ap'
  option ssid 'TestNet'
  option encryption 'psk2'
  option ieee80211k '1'
  option bss_transition '1'
EOF

# Fake package managers
mkdir -p "$ROOT/bin"
PATH_FAKE="$ROOT/bin:$PATH"
cat >"$ROOT/bin/opkg" <<'EOF'
#!/bin/sh
case "$1" in
  list-installed) echo "jsonfilter -"; echo "iwinfo -";;
  update) exit 0;;
  install) echo "(fake) installing $*"; exit 0;;
  *) exit 0;;
esac
EOF
chmod +x "$ROOT/bin/opkg"

# (No umdns listed to force missing detection)

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../" && pwd -P)

run_install() {
  echo "[test] Running install: $*"
  PATH="$PATH_FAKE" RRM_NR_TEST_MODE=1 sh "$REPO_ROOT/scripts/install.sh" --prefix "$ROOT" --no-start --deps-auto-yes --add-sysupgrade "$@" || true
}

run_install

echo "[test] Checking created config"
grep -q 'config rrm_nr' "$ROOT/etc/config/rrm_nr" || { echo '[FAIL] missing rrm_nr config'; exit 1; }

echo "[test] Checking sysupgrade entries"
for f in /etc/init.d/rrm_nr /usr/bin/rrm_nr /lib/rrm_nr_common.sh /etc/config/rrm_nr; do
  grep -qx "$f" "$ROOT/etc/sysupgrade.conf" || { echo "[FAIL] missing $f in sysupgrade.conf"; exit 1; }
done

echo "[test] Forcing second run (should keep existing config)"
before=$(cksum "$ROOT/etc/config/rrm_nr" | awk '{print $1,$2}')
run_install
after=$(cksum "$ROOT/etc/config/rrm_nr" | awk '{print $1,$2}')
[ "$before" = "$after" ] || { echo '[FAIL] config unexpectedly changed without --force-config'; exit 1; }

echo "[test] Force config overwrite"
sleep 1
run_install --force-config
after2=$(cksum "$ROOT/etc/config/rrm_nr" | awk '{print $1,$2}')
[ "$after2" != "$after" ] && echo '[test] overwrite occurred (expected)' || echo '[WARN] overwrite not detected (contents identical)'

echo "[test] Wireless warnings summary (expect at least one warning about ieee80211k)"
grep -Ri 'ieee80211k' "$ROOT" || true

echo "[test] Running auto-fix (--fix-wireless)"
run_install --fix-wireless
grep -q "ieee80211k '1'  # added by rrm_nr" "$ROOT/etc/config/wireless" || { echo '[FAIL] auto-fix did not add ieee80211k'; exit 1; }
grep -q "# rrm_nr wireless auto-fix applied" "$ROOT/etc/config/wireless" || { echo '[FAIL] auto-fix marker missing'; exit 1; }

echo "[test] DONE (basic harness)"

# Cleanup left for manual inspection; uncomment to auto-remove
# rm -rf "$ROOT"
