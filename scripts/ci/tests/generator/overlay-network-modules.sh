#!/usr/bin/env bash
# Overlay network modules: Yggdrasil + IPFS generator wiring and hermetic status.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "overlay-network-modules"
waybar_test_gen_sandbox

mkdir -p "$TEST_DIR/scripts/services/yggdrasil" "$TEST_DIR/scripts/services/ipfs" \
  "$TEST_DIR/scripts/lib" "$TEST_DIR/bin"
cp "$ROOT_DIR/scripts/services/yggdrasil/yggdrasil-status.sh" \
  "$TEST_DIR/scripts/services/yggdrasil/"
cp "$ROOT_DIR/scripts/services/ipfs/ipfs-status.sh" \
  "$TEST_DIR/scripts/services/ipfs/"
chmod +x "$TEST_DIR/scripts/services/yggdrasil/yggdrasil-status.sh" \
  "$TEST_DIR/scripts/services/ipfs/ipfs-status.sh"

# Hermetic signal (status scripts call this after --refresh).
cat >"$TEST_DIR/scripts/lib/waybar-signal.sh" <<'EOF'
#!/usr/bin/env sh
printf 'signal:%s\n' "$*" >>"${WAYBAR_TEST_SIGNAL_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$TEST_DIR/scripts/lib/waybar-signal.sh"

if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before overlay-network checks" >&2
  fail=1
fi

echo "Testing generator wiring for yggdrasil/ipfs..."
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network-custom.generated.jsonc" \
  '
    (."custom/yggdrasil".exec | test("services/yggdrasil/yggdrasil-status\\.sh$"))
    and ."custom/yggdrasil".signal == 37
    and (."custom/yggdrasil"."on-click-middle" | test("yggdrasil-status\\.sh --refresh"))
    and (."custom/yggdrasil"."on-click-middle" | test("waybar-signal\\.sh yggdrasil"))
    and (."custom/yggdrasil"."on-click" | test("yggdrasilctl getPeers"))
    and (."custom/yggdrasil"."on-click-right" | test("systemctl restart.*yggdrasil"))
  ' \
  "custom/yggdrasil should wire status exec, signal 37, clicks, and keyed refresh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network-custom.generated.jsonc" \
  '
    (."custom/ipfs".exec | test("services/ipfs/ipfs-status\\.sh$"))
    and ."custom/ipfs".signal == 38
    and (."custom/ipfs"."on-click-middle" | test("ipfs-status\\.sh --refresh"))
    and (."custom/ipfs"."on-click-middle" | test("waybar-signal\\.sh ipfs"))
    and (."custom/ipfs"."on-click" | test("5001/webui"))
    and (."custom/ipfs"."on-click-right" | test("systemctl restart.*ipfs"))
  ' \
  "custom/ipfs should wire status exec, signal 38, clicks, and keyed refresh"

waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/net".modules | index("custom/yggdrasil") != null)
    and (."group/net".modules | index("custom/ipfs") != null)
    and (."group/net".modules | index("custom/i2pd") != null)
  ' \
  "group/net should include i2pd, yggdrasil, and ipfs"

waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '
    (."custom/net-drawer"."tooltip-format" | test("Yggdrasil"))
    and (."custom/net-drawer"."tooltip-format" | test("IPFS"))
  ' \
  "net-drawer tooltip should list Yggdrasil and IPFS"

waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '
    (.signals.yggdrasil == 37)
    and (.signals.ipfs == 38)
    and (.module_intervals.yggdrasil == "once")
    and (.module_intervals.ipfs == "once")
    and (.services.yggdrasil.endpoint | test("^/") and (test("^unix:") | not))
    and (.services.ipfs.api_url | test("5001"))
  ' \
  "settings should reserve signals/intervals and store a raw ygg socket path (JSONC // trap)"

for script in \
  scripts/services/yggdrasil/yggdrasil-status.sh \
  scripts/services/ipfs/ipfs-status.sh; do
  waybar_test_assert_bash_n "$TEST_DIR/$script" "$script failed bash -n"
  sheb="$(head -1 "$TEST_DIR/$script" || true)"
  case "$sheb" in
    '#!/usr/bin/env bash' | '#!/bin/bash') ;;
    *)
      echo "FAIL: $script must use bash shebang (got: $sheb)" >&2
      fail=1
      ;;
  esac
done

# --- Status runtime: offline / online stubs ---
waybar_test_install_path_stubs
waybar_test_write_bin_stub systemctl <<'EOF'
#!/usr/bin/env sh
# Default: services inactive unless WAYBAR_TEST_*_UP=1
case "$*" in
  *"is-active"*yggdrasil*)
    [ "${WAYBAR_TEST_YGG_UP:-0}" = "1" ] && exit 0
    exit 1
    ;;
  *"is-active"*ipfs*)
    [ "${WAYBAR_TEST_IPFS_UP:-0}" = "1" ] && exit 0
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF
waybar_test_write_bin_stub pgrep <<'EOF'
#!/usr/bin/env sh
exit 1
EOF

echo "Testing yggdrasil offline + online peer parse..."
sig_log=$(mktemp)
out=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/ygg-off" \
    WAYBAR_TEST_SIGNAL_LOG="$sig_log" \
    WAYBAR_TEST_YGG_UP=0 \
    "$TEST_DIR/scripts/services/yggdrasil/yggdrasil-status.sh" --refresh 2>/dev/null | tail -n 1 || true
)
waybar_test_assert_jq "$out" \
  '.class == "offline" and (.text | test("Off"))' \
  "yggdrasil offline: $out"
if ! grep -q 'signal:yggdrasil' "$sig_log"; then
  echo "FAIL: yggdrasil --refresh should call waybar-signal.sh yggdrasil" >&2
  fail=1
fi

waybar_test_write_bin_stub yggdrasilctl <<'EOF'
#!/usr/bin/env sh
# Emit JSON for getSelf / getPeers; reject unknown commands.
case "$*" in
  *getSelf*)
    printf '%s\n' '{"address":"200:abcd::1","subnet":"300:abcd::/64","coords":[1,2,3],"key":"aabb"}'
    ;;
  *getPeers*)
    printf '%s\n' '{"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef":{"remote":"tcp://peer.example:123","uptime":9.5},"cafe":"skip-me"}'
    ;;
  *)
    printf 'fatal: unexpected args %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

: >"$sig_log"
out=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/ygg-on" \
    WAYBAR_TEST_SIGNAL_LOG="$sig_log" \
    WAYBAR_TEST_YGG_UP=1 \
    "$TEST_DIR/scripts/services/yggdrasil/yggdrasil-status.sh" --refresh 2>/dev/null | tail -n 1 || true
)
waybar_test_assert_jq "$out" \
  '.class == "normal" and (.text | test("1")) and (.tooltip | test("200:abcd::1")) and (.tooltip | test("Peers: 1"))' \
  "yggdrasil online peer count + address: $out"

# Non-JSON stdout from yggdrasilctl → warning (permission denied path)
waybar_test_write_bin_stub yggdrasilctl <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "Fatal error: dial unix /var/run/yggdrasil.sock: connect: permission denied"
exit 1
EOF
out=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/ygg-warn" \
    WAYBAR_TEST_SIGNAL_LOG="/dev/null" \
    WAYBAR_TEST_YGG_UP=1 \
    "$TEST_DIR/scripts/services/yggdrasil/yggdrasil-status.sh" --refresh 2>/dev/null | tail -n 1 || true
)
waybar_test_assert_jq "$out" \
  '.class == "warning" and (.tooltip | test("admin socket unreachable"; "i"))' \
  "yggdrasil non-JSON ctl output should warn: $out"

echo "Testing ipfs offline + online swarm parse..."
waybar_test_write_bin_stub curl <<'EOF'
#!/usr/bin/env sh
# Fail by default (offline). Online stubs key off WAYBAR_TEST_IPFS_API=1.
[ "${WAYBAR_TEST_IPFS_API:-0}" = "1" ] || exit 1
url=""
for a in "$@"; do
  case "$a" in
    http*|https*) url=$a ;;
  esac
done
case "$url" in
  */api/v0/id)
    printf '%s\n' '{"ID":"QmTestPeerIdABCDEFGH","AgentVersion":"kubo/0.42.0"}'
    ;;
  */api/v0/swarm/peers)
    printf '%s\n' '{"Peers":[{"Peer":"a"},{"Peer":"b"},{"Peer":"c"}]}'
    ;;
  */api/v0/stats/bw)
    printf '%s\n' '{"RateIn":2048,"RateOut":1024,"TotalIn":1048576,"TotalOut":512000}'
    ;;
  *)
    exit 1
    ;;
esac
EOF

out=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/ipfs-off" \
    WAYBAR_TEST_SIGNAL_LOG="/dev/null" \
    WAYBAR_TEST_IPFS_UP=0 \
    WAYBAR_TEST_IPFS_API=0 \
    "$TEST_DIR/scripts/services/ipfs/ipfs-status.sh" --refresh 2>/dev/null | tail -n 1 || true
)
waybar_test_assert_jq "$out" \
  '.class == "offline" and (.text | test("Off"))' \
  "ipfs offline: $out"

sig_log2=$(mktemp)
out=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/ipfs-on" \
    WAYBAR_TEST_SIGNAL_LOG="$sig_log2" \
    WAYBAR_TEST_IPFS_UP=1 \
    WAYBAR_TEST_IPFS_API=1 \
    "$TEST_DIR/scripts/services/ipfs/ipfs-status.sh" --refresh 2>/dev/null | tail -n 1 || true
)
waybar_test_assert_jq "$out" \
  '.class == "normal" and (.text | test("3")) and (.tooltip | test("Swarm peers: 3")) and (.tooltip | test("kubo/0.42.0"))' \
  "ipfs online swarm peers + agent: $out"
if ! grep -q 'signal:ipfs' "$sig_log2"; then
  echo "FAIL: ipfs --refresh should call waybar-signal.sh ipfs" >&2
  fail=1
fi
rm -f "$sig_log" "$sig_log2"

echo "Testing click overrides from services.* settings..."
waybar_test_compile_settings
jq '
  .services.yggdrasil.on_click = "TEST_YGG_CLICK"
  | .services.ipfs.on_click = "TEST_IPFS_CLICK"
  | .services.ipfs.webui_url = "http://ipfs.override/webui"
' "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed after click overrides" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network-custom.generated.jsonc" \
  '."custom/yggdrasil"."on-click" == "TEST_YGG_CLICK" and ."custom/ipfs"."on-click" == "TEST_IPFS_CLICK"' \
  "services.*.on_click overrides should win"

# CSS pills include new modules (SoT → generated).
if ! grep -Fq '#custom-yggdrasil' "$TEST_DIR/theme/module-pills.generated.css"; then
  echo "FAIL: #custom-yggdrasil missing from module-pills.generated.css" >&2
  fail=1
fi
if ! grep -Fq '#custom-ipfs' "$TEST_DIR/theme/module-pills.generated.css"; then
  echo "FAIL: #custom-ipfs missing from module-pills.generated.css" >&2
  fail=1
fi

echo "PASS: overlay-network-modules"
waybar_test_end
