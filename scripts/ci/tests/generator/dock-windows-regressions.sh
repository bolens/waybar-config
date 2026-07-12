#!/usr/bin/env bash
# Regressions for dock-windows focus/order bugs:
# - Waybar on-click lacks WAYBAR_OUTPUT_NAME (Alexays/Waybar#3848) → wrong global slot
# - steam_app_* must not collapse onto Steam client appicon key
# - --focus-only must keep list cache; full signal must drop it
# - live active highlight from active-window-title*.raw
# - glyph flash: warm/cold appicon paths must keep .appicon + empty text without re-resolve
# - appicon cache: offline hot path, miss stamps, prefetch skip-if-warm
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "dock-windows-regressions"
waybar_test_gen_sandbox

echo "Testing dock-windows focus/order regressions..."

mkdir -p "$TEST_DIR/scripts/dock" "$TEST_DIR/scripts/lib" "$TEST_DIR/scripts/generate"
cp "$ROOT_DIR/scripts/dock/dock-windows-click.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-signal.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-query.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-slot-status.sh" \
  "$TEST_DIR/scripts/dock/"
cp "$ROOT_DIR/scripts/lib/dock-windows-kde-lib.sh" \
  "$ROOT_DIR/scripts/lib/dock-windows-kde-lib.py" \
  "$ROOT_DIR/scripts/lib/compositor-session.sh" \
  "$ROOT_DIR/scripts/lib/waybar-cache-helpers.sh" \
  "$ROOT_DIR/scripts/lib/waybar-settings.sh" \
  "$TEST_DIR/scripts/lib/"
cp "$ROOT_DIR/scripts/generate/generate-dock-windows-modules.sh" "$TEST_DIR/scripts/generate/"
cp "$ROOT_DIR/scripts/generate/generate-dock-windows-css.sh" "$TEST_DIR/scripts/generate/" 2>/dev/null || \
  cp "$ROOT_DIR/scripts/generate/generate-dock-windows-css.sh" "$TEST_DIR/scripts/generate/"
# css generator deps
mkdir -p "$TEST_DIR/scripts/lib"
cp "$ROOT_DIR/scripts/lib/css-selectors-lib.sh" "$TEST_DIR/scripts/lib/" 2>/dev/null || true
cp "$ROOT_DIR/scripts/lib/appicon-lib.sh" "$TEST_DIR/scripts/lib/" 2>/dev/null || true
waybar_test_install_script_stubs
chmod +x "$TEST_DIR"/scripts/dock/*.sh \
  "$TEST_DIR/scripts/lib/dock-windows-kde-lib.sh" \
  "$TEST_DIR/scripts/lib/dock-windows-kde-lib.py" \
  "$TEST_DIR/scripts/generate/generate-dock-windows-modules.sh"
[ -f "$TEST_DIR/scripts/generate/generate-dock-windows-css.sh" ] && chmod +x "$TEST_DIR/scripts/generate/generate-dock-windows-css.sh"

# --- Generated wiring: exec has OUTPUT_NAME; on-click must not (empty expansion bug) ---
"$TEST_DIR/scripts/generate/generate-dock-windows-modules.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  '."custom/dock-win-0".exec | test("WAYBAR_OUTPUT_NAME")' \
  "dock-win exec must pass \$WAYBAR_OUTPUT_NAME"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  '(."custom/dock-win-0"."on-click" | test("WAYBAR_OUTPUT_NAME")) | not' \
  "dock-win on-click must NOT expand \$WAYBAR_OUTPUT_NAME (Waybar omits it)"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  '(."custom/dock-win-0"."on-click-right" | test("WAYBAR_OUTPUT_NAME")) | not' \
  "dock-win on-click-right must NOT expand \$WAYBAR_OUTPUT_NAME"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  '(."custom/dock-win-0"."on-click-middle" | test("WAYBAR_OUTPUT_NAME")) | not' \
  "dock-win on-click-middle must NOT expand \$WAYBAR_OUTPUT_NAME"

# --- appicon key: steam game ≠ steam client ---
# shellcheck source=dock-windows-kde-lib.sh
. "$TEST_DIR/scripts/lib/dock-windows-kde-lib.sh"
# Ensure assoc arrays exist before key lookups under `set -u`.
declare -A DOCK_WINDOWS_APP_ID=()
declare -A DOCK_WINDOWS_ICON_MAP=()
dock_windows_load_icon_map || true
steam_key="$(dock_windows_appicon_key_for 'Steam' 'steam' || true)"
game_key="$(dock_windows_appicon_key_for 'Tap Ninja' 'steam_app_1891700' || true)"
if [ "$steam_key" != "steam" ]; then
  echo "FAIL: Steam client key expected 'steam', got '$steam_key'" >&2
  fail=1
else
  echo "PASS: Steam client appicon key is steam"
fi
if [ "$game_key" != "steam-app-1891700" ]; then
  echo "FAIL: steam_app_* key expected 'steam-app-1891700', got '$game_key'" >&2
  fail=1
else
  echo "PASS: steam_app_* stays distinct from steam"
fi
# Substring trap: class containing "steam" must not become steam via fuzzy map
bad="$(dock_windows_appicon_key_for 'Some Game' 'steam_app_42' || true)"
if [ "$bad" = "steam" ]; then
  echo "FAIL: steam_app_42 must not resolve to steam" >&2
  fail=1
fi

# --- normalize / resolve output helpers ---
norm="$(dock_windows_normalize_output_arg '$WAYBAR_OUTPUT_NAME')"
if [ -n "$norm" ]; then
  echo "FAIL: literal \$WAYBAR_OUTPUT_NAME should normalize to empty, got '$norm'" >&2
  fail=1
else
  echo "PASS: literal \$WAYBAR_OUTPUT_NAME normalized away"
fi

# --- Dual-output + steam fixture with qdbus stubs ---
waybar_test_install_path_stubs
FIXTURE="$ROOT_DIR/scripts/ci/lib/fixtures/windows-runner/golden-dual-steam.txt"
FIXTURE_DATA=$(cat "$FIXTURE")
export WAYBAR_TEST_QDBUS_LOG="$TEST_DIR/qdbus-calls.log"
: >"$WAYBAR_TEST_QDBUS_LOG"
waybar_test_write_bin_stub qdbus6 <<EOF
#!/usr/bin/env sh
echo "\$*" >>"\$WAYBAR_TEST_QDBUS_LOG"
case " \$* " in
  *"org.kde.KWin.activeOutputName"*)
    printf '%s\n' "\${WAYBAR_TEST_ACTIVE_OUTPUT:-DP-1}"
    ;;
  *"org.kde.krunner1.Match"*)
    cat <<'GOLD'
$FIXTURE_DATA
GOLD
    ;;
  *"org.kde.krunner1.Run"*)
    exit 0
    ;;
  *"org.kde.kwin.Scripting"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

CACHE="$TEST_DIR/cache-reg"
rm -rf "$CACHE"
mkdir -p "$CACHE/waybar" "$TEST_DIR/runtime"
export XDG_CACHE_HOME="$CACHE" XDG_RUNTIME_DIR="$TEST_DIR/runtime"
export WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" WAYBAR_COMPOSITOR=kde
export WAYBAR_TEST_ACTIVE_OUTPUT=DP-1

# Global list slot 0 is Helium (HDMI); DP-1 slot 0 is Terminal.
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
global0=$(
  env -u WAYBAR_OUTPUT_NAME \
    "$TEST_DIR/scripts/dock/dock-windows-query.sh" "" | jq -r '.[0].title // empty'
)
dp1_0=$(
  WAYBAR_OUTPUT_NAME=DP-1 \
    "$TEST_DIR/scripts/dock/dock-windows-query.sh" DP-1 | jq -r '.[0].title // empty'
)
if [ "$global0" != "Helium on HDMI-A-1" ]; then
  echo "FAIL: expected global[0]=Helium, got '$global0'" >&2
  fail=1
else
  echo "PASS: global list leads with HDMI Helium"
fi
if [ "$dp1_0" != "Terminal on DP-1" ]; then
  echo "FAIL: expected DP-1[0]=Terminal, got '$dp1_0'" >&2
  fail=1
else
  echo "PASS: DP-1 filtered list leads with Terminal"
fi

# Status (exec path) binds slot 0 → Terminal on DP-1
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
printf '%s' 'Terminal on DP-1' >"$CACHE/waybar/active-window-title-DP-1.raw"
slot0=$(
  WAYBAR_OUTPUT_NAME=DP-1 \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 0 DP-1
)
waybar_test_assert_jq "$slot0" '.tooltip == "Terminal on DP-1"' \
  "DP-1 slot 0 tooltip should be Terminal: $slot0"
waybar_test_assert_jq "$slot0" '.class | index("dock-win-active")' \
  "live title match should mark slot active: $slot0"

bind="$XDG_RUNTIME_DIR/waybar-dock/slots/DP-1/0.json"
if [ ! -f "$bind" ]; then
  echo "FAIL: slot-status should write bind file $bind" >&2
  fail=1
else
  waybar_test_assert_json_file_jq "$bind" \
    '.title == "Terminal on DP-1" and (.id | test("terminal000001"))' \
    "bind file should record Terminal id"
  echo "PASS: slot bind file written for DP-1/0"
fi

# Also bind steam + game slots and assert distinct appicon classes when pngs exist
mkdir -p "$TEST_DIR/theme/dock-appicons"
# minimal png
export TEST_DIR
python3 - <<'PY'
import struct, zlib, pathlib, os
dest_dir = pathlib.Path(os.environ["TEST_DIR"]) / "theme" / "dock-appicons"
sig = b"\x89PNG\r\n\x1a\n"
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
raw = zlib.compress(b"\x00" + b"\x00\x00\x00\xff")
png = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
for name in ("steam.png", "steam-app-1891700.png", "terminal.png"):
    (dest_dir / name).write_bytes(png)
PY
waybar_test_patch_settings '.icons.appicon.enabled = true'
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
steam_slot=$(
  WAYBAR_OUTPUT_NAME=DP-1 \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
game_slot=$(
  WAYBAR_OUTPUT_NAME=DP-1 \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 2 DP-1
)
waybar_test_assert_jq "$steam_slot" '.class | index("appicon-steam")' \
  "Steam client slot class: $steam_slot"
waybar_test_assert_jq "$game_slot" \
  '(.class | index("appicon-steam-app-1891700")) and ((.class | map(select(. == "appicon-steam")) | length) == 0)' \
  "Steam game slot must use steam-app id, not appicon-steam: $game_slot"

# Click WITHOUT WAYBAR_OUTPUT_NAME (Waybar on-click) must focus Terminal, not Helium
: >"$WAYBAR_TEST_QDBUS_LOG"
env -u WAYBAR_OUTPUT_NAME \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_COMPOSITOR=kde WAYBAR_TEST_ACTIVE_OUTPUT=DP-1 \
  XDG_CACHE_HOME="$CACHE" XDG_RUNTIME_DIR="$TEST_DIR/runtime" \
  "$TEST_DIR/scripts/dock/dock-windows-click.sh" focus 0
run_line=$(grep 'org.kde.krunner1.Run' "$WAYBAR_TEST_QDBUS_LOG" | head -1 || true)
case "$run_line" in
  *terminal000001*)
    echo "PASS: on-click without OUTPUT_NAME focuses DP-1 bind (Terminal)"
    ;;
  *helium00000001*)
    echo "FAIL: on-click focused global Helium instead of DP-1 Terminal" >&2
    echo "  run: $run_line" >&2
    fail=1
    ;;
  *)
    echo "FAIL: expected Run with Terminal id; got: $run_line" >&2
    cat "$WAYBAR_TEST_QDBUS_LOG" >&2 || true
    fail=1
    ;;
esac

# Literal \$WAYBAR_OUTPUT_NAME argv must not wipe resolved output
: >"$WAYBAR_TEST_QDBUS_LOG"
env -u WAYBAR_OUTPUT_NAME \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_COMPOSITOR=kde WAYBAR_TEST_ACTIVE_OUTPUT=DP-1 \
  XDG_CACHE_HOME="$CACHE" XDG_RUNTIME_DIR="$TEST_DIR/runtime" \
  "$TEST_DIR/scripts/dock/dock-windows-click.sh" focus 0 '$WAYBAR_OUTPUT_NAME'
run_line=$(grep 'org.kde.krunner1.Run' "$WAYBAR_TEST_QDBUS_LOG" | head -1 || true)
case "$run_line" in
  *terminal000001*)
    echo "PASS: literal \$WAYBAR_OUTPUT_NAME argv still focuses Terminal bind"
    ;;
  *)
    echo "FAIL: literal OUTPUT_NAME argv broke bind focus: $run_line" >&2
    fail=1
    ;;
esac

# --- focus-only keeps list cache; full signal drops it ---
list_cache="$CACHE/waybar/dock-windows-list.DP-1.json"
mkdir -p "$CACHE/waybar"
printf '[]\n' >"$list_cache"
"$TEST_DIR/scripts/dock/dock-windows-signal.sh" --force --focus-only
if [ ! -f "$list_cache" ]; then
  echo "FAIL: --focus-only must keep dock-windows-list cache" >&2
  fail=1
else
  echo "PASS: --focus-only keeps list cache"
fi
"$TEST_DIR/scripts/dock/dock-windows-signal.sh" --force
if [ -f "$list_cache" ]; then
  echo "FAIL: full dock-windows-signal must drop list cache" >&2
  fail=1
else
  echo "PASS: full signal drops list cache"
fi

# Live highlight: change active title without rebuilding list → inactive→active flip
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
printf '%s' 'Steam' >"$CACHE/waybar/active-window-title-DP-1.raw"
steam_now=$(
  WAYBAR_OUTPUT_NAME=DP-1 \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
term_now=$(
  WAYBAR_OUTPUT_NAME=DP-1 \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 0 DP-1
)
waybar_test_assert_jq "$steam_now" '.class | index("dock-win-active")' \
  "Steam slot active when title=Steam: $steam_now"
waybar_test_assert_jq "$term_now" '.class | index("dock-win-inactive")' \
  "Terminal slot inactive when title=Steam: $term_now"

# --- Glyph flash regressions (focus/signal must not drop PNG classes) ---
# Warm launcher PNG: failing APPICON_BIN must still keep .appicon + empty text.
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
exit 1
EOF
export APPICON_BIN="$TEST_DIR/bin/appicon" WAYBAR_TEST_APPICON_LOG="$TEST_DIR/appicon-calls.log"
: >"$WAYBAR_TEST_APPICON_LOG"
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
warm=$(
  WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
waybar_test_assert_jq "$warm" \
  '(.class | index("appicon")) and (.class | index("appicon-steam")) and (.text == "")' \
  "warm launcher PNG must keep appicon class + empty glyph text: $warm"
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: warm PNG path should not call appicon resolve: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: warm PNG path skips appicon resolve"
fi

# Repeated focus-style refreshes must not drop .appicon (the flash path).
: >"$WAYBAR_TEST_APPICON_LOG"
glyph_flash_ok=1
for _i in 1 2 3; do
  tick=$(
    WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
      "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
  )
  if ! printf '%s' "$tick" | jq -e \
    '(.class | index("appicon-steam")) and (.text == "")' >/dev/null; then
    echo "FAIL: refresh $_i dropped appicon / restored glyph: $tick" >&2
    glyph_flash_ok=0
    fail=1
    break
  fi
done
if [ "$glyph_flash_ok" = 1 ]; then
  echo "PASS: repeated slot refreshes keep appicon (no glyph flash)"
fi
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: focus refreshes must not call appicon resolve: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
fi

# Warm dock-win-icons PNG (no launcher png) still keeps .appicon without resolve.
rm -f "$TEST_DIR/theme/dock-appicons/steam.png"
mkdir -p "$TEST_DIR/theme/dock-win-icons"
cp "$TEST_DIR/theme/dock-appicons/terminal.png" "$TEST_DIR/theme/dock-win-icons/steam.png"
: >"$WAYBAR_TEST_APPICON_LOG"
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
warm_win=$(
  WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
waybar_test_assert_jq "$warm_win" \
  '(.class | index("appicon-steam")) and (.text == "")' \
  "warm dock-win-icons PNG must keep appicon + empty text: $warm_win"
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: dock-win-icons warm path should not call appicon: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: warm dock-win-icons path skips appicon resolve"
fi

# Known dock-apps key without PNG: emit .appicon, try offline cache fill once, then miss-stamp.
rm -f "$TEST_DIR/theme/dock-appicons/steam.png" "$TEST_DIR/theme/dock-win-icons/steam.png"
rm -rf "$CACHE/waybar/appicon-miss"
: >"$WAYBAR_TEST_APPICON_LOG"
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
cold_key=$(
  WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
waybar_test_assert_jq "$cold_key" \
  '(.class | index("appicon")) and (.class | index("appicon-steam")) and (.text == "")' \
  "known dock-apps id without PNG must still emit appicon + empty text: $cold_key"
if ! grep -q -- '--offline' "$WAYBAR_TEST_APPICON_LOG"; then
  echo "FAIL: cold fill must use appicon --offline: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: cold known-key fill uses --offline"
fi
# Second refresh must not re-spawn (miss stamp).
: >"$WAYBAR_TEST_APPICON_LOG"
cold_key2=$(
  WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
waybar_test_assert_jq "$cold_key2" \
  '(.class | index("appicon-steam")) and (.text == "")' \
  "miss-stamped known key still emits appicon: $cold_key2"
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: miss stamp must skip re-resolve: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: miss stamp skips repeated cold resolve"
fi

# Offline cache hit materializes theme PNG and clears miss stamp.
fake_src="$TEST_DIR/fake-icons/steam-src.png"
mkdir -p "$TEST_DIR/fake-icons"
python3 - <<'PY'
import struct, zlib, pathlib, os
dest = pathlib.Path(os.environ["TEST_DIR"]) / "fake-icons" / "steam-src.png"
sig = b"\x89PNG\r\n\x1a\n"
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
raw = zlib.compress(b"\x00" + b"\x00\x00\x00\xff")
png = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
dest.write_bytes(png)
PY
waybar_test_write_bin_stub appicon <<EOF
#!/usr/bin/env sh
echo "appicon-called \$*" >>"\${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
case " \$* " in
  *" --offline "*) printf '%s\n' "$fake_src"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
rm -rf "$CACHE/waybar/appicon-miss"
rm -f "$TEST_DIR/theme/dock-appicons/steam.png" "$TEST_DIR/theme/dock-win-icons/steam.png"
: >"$WAYBAR_TEST_APPICON_LOG"
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
filled=$(
  WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
waybar_test_assert_jq "$filled" \
  '(.class | index("appicon-steam")) and (.text == "")' \
  "offline cache hit should keep appicon class: $filled"
if [ ! -f "$TEST_DIR/theme/dock-appicons/steam.png" ]; then
  echo "FAIL: offline hit should materialize theme/dock-appicons/steam.png" >&2
  fail=1
else
  echo "PASS: offline cache hit materializes dock-appicons PNG"
fi
if [ -f "$CACHE/waybar/appicon-miss/steam" ]; then
  echo "FAIL: successful fill should clear miss stamp" >&2
  fail=1
else
  echo "PASS: successful fill clears miss stamp"
fi
# Warm after fill: no further resolve.
: >"$WAYBAR_TEST_APPICON_LOG"
filled2=$(
  WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 1 DP-1
)
waybar_test_assert_jq "$filled2" '.class | index("appicon-steam")' "post-fill warm: $filled2"
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: warm after fill must not resolve: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: warm after offline fill skips resolve"
fi

# Prefetch skips warm PNGs (no appicon spawn) and reports cached count.
cp "$ROOT_DIR/scripts/dock/dock-appicon-prefetch.sh" "$TEST_DIR/scripts/dock/"
chmod +x "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh"
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
exit 1
EOF
mkdir -p "$TEST_DIR/theme/dock-appicons"
python3 - <<'PY'
import json, struct, zlib, pathlib, os
root = pathlib.Path(os.environ["TEST_DIR"])
manifest = json.loads((root / "data" / "dock-apps.json").read_text())
sig = b"\x89PNG\r\n\x1a\n"
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
raw = zlib.compress(b"\x00" + b"\x00\x00\x00\xff")
png = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
out = root / "theme" / "dock-appicons"
for key in manifest:
    (out / f"{key}.png").write_bytes(png)
PY
: >"$WAYBAR_TEST_APPICON_LOG"
prefetch_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" 2>&1
) || true
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: prefetch must skip existing PNGs: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  echo "  out: $prefetch_out" >&2
  fail=1
elif ! printf '%s' "$prefetch_out" | grep -Eq '[1-9][0-9]* cached'; then
  echo "FAIL: prefetch should report cached skips: $prefetch_out" >&2
  fail=1
else
  echo "PASS: prefetch skips warm PNGs ($prefetch_out)"
fi

# Launcher status warm path: existing PNG → .appicon + empty text, no resolve.
cp "$ROOT_DIR/scripts/dock/dock-launcher.sh" "$TEST_DIR/scripts/dock/"
chmod +x "$TEST_DIR/scripts/dock/dock-launcher.sh"
mkdir -p "$TEST_DIR/theme/dock-appicons"
python3 - <<'PY'
import struct, zlib, pathlib, os
dest = pathlib.Path(os.environ["TEST_DIR"]) / "theme" / "dock-appicons" / "browser.png"
sig = b"\x89PNG\r\n\x1a\n"
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
raw = zlib.compress(b"\x00" + b"\x00\x00\x00\xff")
png = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
dest.write_bytes(png)
PY
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
exit 1
EOF
: >"$WAYBAR_TEST_APPICON_LOG"
launcher_warm=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-launcher.sh" browser status
)
waybar_test_assert_jq "$launcher_warm" \
  '(.class | index("appicon")) and (.text == "")' \
  "launcher warm PNG must keep appicon + empty glyph text: $launcher_warm"
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: launcher warm path should not call appicon resolve: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: launcher warm PNG skips appicon resolve"
fi

# Generic .appicon glyph-hide rule: font-size:0 + transparent (not just per-app classes).
"$TEST_DIR/scripts/generate/generate-dock-windows-css.sh"
css="$TEST_DIR/theme/dock-windows.generated.css"
if ! grep -Fq 'Hide glyph text whenever .appicon is set' "$css"; then
  echo "FAIL: dock-windows CSS missing generic .appicon glyph-hide comment" >&2
  fail=1
elif ! awk '
  /Hide glyph text whenever \.appicon is set/ { inblock=1; next }
  inblock && /font-size: 0/ { found_fs=1 }
  inblock && /color: transparent/ { found_c=1 }
  inblock && /^}/ {
    exit !(found_fs && found_c)
  }
' "$css"; then
  echo "FAIL: generic .appicon rule must set font-size:0 and color:transparent" >&2
  fail=1
else
  echo "PASS: dock-windows CSS hides glyphs for generic .appicon"
fi

waybar_test_end
