#!/usr/bin/env bash
# Unit + integration coverage for appicon caching helpers and dock hot/prefetch paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "dock-appicon-cache"
waybar_test_gen_sandbox

echo "Testing appicon cache helpers + dock prefetch/hot paths..."

write_png() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  python3 - "$dest" <<'PY'
import struct, zlib, pathlib, sys
dest = pathlib.Path(sys.argv[1])
sig = b"\x89PNG\r\n\x1a\n"
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
raw = zlib.compress(b"\x00" + b"\x00\x00\x00\xff")
png = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
dest.write_bytes(png)
PY
}

CACHE="$TEST_DIR/cache-appicon"
rm -rf "$CACHE"
mkdir -p "$CACHE" "$TEST_DIR/runtime" "$TEST_DIR/bin" "$TEST_DIR/fake-icons"
export XDG_CACHE_HOME="$CACHE" XDG_RUNTIME_DIR="$TEST_DIR/runtime"
export WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts"
export WAYBAR_TEST_APPICON_LOG="$TEST_DIR/appicon-calls.log"

# Ensure live copies of the caching code under test.
cp "$ROOT_DIR/scripts/lib/appicon-lib.sh" "$TEST_DIR/scripts/lib/"
cp "$ROOT_DIR/scripts/dock/dock-appicon-prefetch.sh" \
  "$ROOT_DIR/scripts/dock/dock-launcher.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-slot-status.sh" \
  "$TEST_DIR/scripts/dock/"
chmod +x "$TEST_DIR"/scripts/dock/*.sh

# shellcheck source=../../../lib/waybar-settings.sh
. "$TEST_DIR/scripts/lib/waybar-settings.sh"
# shellcheck source=../../../lib/appicon-lib.sh
. "$TEST_DIR/scripts/lib/appicon-lib.sh"

waybar_test_patch_settings \
  '.icons.appicon.enabled = true | .icons.appicon.size = 18 | .icons.appicon.theme = "dark"'

# --- miss stamp helpers ---
rm -rf "$(waybar_appicon_miss_dir)"
if waybar_appicon_miss_fresh "steam"; then
  echo "FAIL: miss_fresh should be false with no stamp" >&2
  fail=1
else
  echo "PASS: miss_fresh false without stamp"
fi
waybar_appicon_miss_mark "steam"
if [ ! -f "$CACHE/waybar/appicon-miss/steam" ]; then
  echo "FAIL: miss_mark should create stamp under XDG_CACHE_HOME/waybar/appicon-miss" >&2
  fail=1
fi
if ! waybar_appicon_miss_fresh "steam" 300; then
  echo "FAIL: miss_fresh should be true for new stamp" >&2
  fail=1
else
  echo "PASS: miss_mark + miss_fresh"
fi
waybar_appicon_miss_clear "steam"
if waybar_appicon_miss_fresh "steam"; then
  echo "FAIL: miss_clear should remove stamp" >&2
  fail=1
else
  echo "PASS: miss_clear removes stamp"
fi

# Expired stamp (mtime in the past beyond TTL) must not be fresh.
waybar_appicon_miss_mark "expired"
touch -d '10 minutes ago' "$CACHE/waybar/appicon-miss/expired" 2>/dev/null \
  || touch -t 202001010000 "$CACHE/waybar/appicon-miss/expired"
if waybar_appicon_miss_fresh "expired" 60; then
  echo "FAIL: expired stamp must not be miss_fresh (ttl=60)" >&2
  fail=1
else
  echo "PASS: expired miss stamp is not fresh"
fi

# --- resolve online vs offline ---
waybar_test_install_path_stubs
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
out="${WAYBAR_TEST_APPICON_SRC:-}"
if [ -n "$out" ] && [ -f "$out" ]; then
  printf '%s\n' "$out"
  exit 0
fi
exit 1
EOF
export APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH"
write_png "$TEST_DIR/fake-icons/src.png"
export WAYBAR_TEST_APPICON_SRC="$TEST_DIR/fake-icons/src.png"

: >"$WAYBAR_TEST_APPICON_LOG"
if ! path="$(waybar_appicon_resolve "browser" 18 dark offline)"; then
  echo "FAIL: offline resolve should succeed with stub src" >&2
  fail=1
elif [ "$path" != "$TEST_DIR/fake-icons/src.png" ]; then
  echo "FAIL: offline resolve path mismatch: $path" >&2
  fail=1
elif ! grep -q -- '--offline' "$WAYBAR_TEST_APPICON_LOG"; then
  echo "FAIL: offline mode must pass --offline: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: waybar_appicon_resolve offline"
fi

: >"$WAYBAR_TEST_APPICON_LOG"
if ! path="$(waybar_appicon_resolve "browser" 18 dark online)"; then
  echo "FAIL: online resolve should succeed with stub src" >&2
  fail=1
elif grep -q -- '--offline' "$WAYBAR_TEST_APPICON_LOG"; then
  echo "FAIL: online mode must not pass --offline: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: waybar_appicon_resolve online"
fi

if waybar_appicon_resolve "" 18 dark offline 2>/dev/null; then
  echo "FAIL: empty query must fail" >&2
  fail=1
else
  echo "PASS: empty query rejected"
fi

# --- materialize warm skip + rematerialize ---
dest_base="$TEST_DIR/theme/dock-appicons/mat-test"
mkdir -p "$(dirname "$dest_base")"
printf 'ORIGINAL-PNG-BYTES\n' >"${dest_base}.png"
before_sum="$(cksum <"${dest_base}.png")"
waybar_test_write_bin_stub magick <<'EOF'
#!/usr/bin/env sh
echo "magick-called $*" >>"${WAYBAR_TEST_MAGICK_LOG:-/dev/null}"
# Mimic ImageMagick: last arg is png32:/dest
dest=$(printf '%s\n' "$@" | awk 'END{print}' | sed 's/^png32://')
src=$1
if [ "${WAYBAR_TEST_MAGICK_FAIL:-0}" = "1" ]; then
  exit 1
fi
cp "$src" "$dest"
EOF
export WAYBAR_TEST_MAGICK_LOG="$TEST_DIR/magick-calls.log"
: >"$WAYBAR_TEST_MAGICK_LOG"
export WAYBAR_TEST_MAGICK_FAIL=0
if ! waybar_appicon_materialize "$TEST_DIR/fake-icons/src.png" "$dest_base" 18; then
  echo "FAIL: warm materialize should succeed without re-rasterize" >&2
  fail=1
elif [ -s "$WAYBAR_TEST_MAGICK_LOG" ]; then
  echo "FAIL: warm materialize must not call magick: $(cat "$WAYBAR_TEST_MAGICK_LOG")" >&2
  fail=1
elif [ "$(cksum <"${dest_base}.png")" != "$before_sum" ]; then
  echo "FAIL: warm materialize must keep existing PNG bytes" >&2
  fail=1
else
  echo "PASS: materialize skips existing PNG"
fi

# REMATERIALIZE=1 must invoke magick (stub fails → materialize fails).
: >"$WAYBAR_TEST_MAGICK_LOG"
export WAYBAR_TEST_MAGICK_FAIL=1
if WAYBAR_APPICON_REMATERIALIZE=1 waybar_appicon_materialize "$TEST_DIR/fake-icons/src.png" "$dest_base" 18; then
  echo "FAIL: REMATERIALIZE with failing magick should fail" >&2
  fail=1
elif [ ! -s "$WAYBAR_TEST_MAGICK_LOG" ]; then
  echo "FAIL: REMATERIALIZE=1 must invoke magick" >&2
  fail=1
else
  echo "PASS: REMATERIALIZE=1 invokes rasterizer (and can fail)"
fi

# Fresh dest: magick stub succeeds → dest.png created.
export WAYBAR_TEST_MAGICK_FAIL=0
copy_dest="$TEST_DIR/theme/dock-appicons/copy-test"
rm -f "${copy_dest}.png" "$copy_dest"
: >"$WAYBAR_TEST_MAGICK_LOG"
if waybar_appicon_materialize "$TEST_DIR/fake-icons/src.png" "$copy_dest" 18 \
  && [ -f "${copy_dest}.png" ]; then
  echo "PASS: materialize creates dest.png"
else
  echo "FAIL: materialize must create ${copy_dest}.png (log=$(cat "$WAYBAR_TEST_MAGICK_LOG" 2>/dev/null))" >&2
  fail=1
fi
unset WAYBAR_TEST_MAGICK_FAIL

# --- prefetch: online for missing; keep PNG on miss; FORCE re-resolves ---
cp "$ROOT_DIR/scripts/dock/dock-appicon-prefetch.sh" "$TEST_DIR/scripts/dock/"
chmod +x "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh"

# Minimal manifest so prefetch is fast/deterministic.
cat >"$TEST_DIR/data/dock-apps.json" <<'JSON'
{
  "browser": { "name": "Browser", "appicon": "browser", "icon": "󰈹" },
  "terminal": { "name": "Terminal", "appicon": "konsole", "icon": "" }
}
JSON
mkdir -p "$TEST_DIR/theme/dock-appicons"
write_png "$TEST_DIR/theme/dock-appicons/browser.png"
rm -f "$TEST_DIR/theme/dock-appicons/terminal.png"
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
case "$*" in
  *konsole*|*terminal*)
    printf '%s\n' "${WAYBAR_TEST_APPICON_SRC}"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
: >"$WAYBAR_TEST_APPICON_LOG"
prefetch_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" 2>&1
) || true
if grep -q -- '--offline' "$WAYBAR_TEST_APPICON_LOG"; then
  echo "FAIL: prefetch must use online resolve: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
elif ! grep -q 'konsole\|terminal' "$WAYBAR_TEST_APPICON_LOG"; then
  echo "FAIL: prefetch should resolve missing terminal: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
elif grep -E 'browser' "$WAYBAR_TEST_APPICON_LOG" | grep -vq 'konsole'; then
  # browser should be skipped (warm); only terminal resolved
  if grep -q ' resolve .*browser' "$WAYBAR_TEST_APPICON_LOG" \
    || grep -Eq 'resolve .* browser( |$)' "$WAYBAR_TEST_APPICON_LOG"; then
    echo "FAIL: prefetch should skip warm browser.png: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
    fail=1
  fi
fi
if ! printf '%s' "$prefetch_out" | grep -Eq '1 cached'; then
  echo "FAIL: prefetch should report 1 cached (browser): $prefetch_out" >&2
  fail=1
elif [ ! -f "$TEST_DIR/theme/dock-appicons/terminal.png" ]; then
  echo "FAIL: prefetch should materialize terminal.png" >&2
  fail=1
else
  echo "PASS: prefetch online-fills missing, skips warm ($prefetch_out)"
fi

# Keep warm PNG when resolve fails (FORCE path with failing bin).
browser_sum="$(cksum <"$TEST_DIR/theme/dock-appicons/browser.png")"
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
exit 1
EOF
: >"$WAYBAR_TEST_APPICON_LOG"
keep_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    XDG_CACHE_HOME="$CACHE" \
    WAYBAR_APPICON_PREFETCH_FORCE=1 \
    "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" 2>&1
) || true
if [ ! -f "$TEST_DIR/theme/dock-appicons/browser.png" ]; then
  echo "FAIL: prefetch must not delete warm PNG on miss: $keep_out" >&2
  fail=1
elif [ "$(cksum <"$TEST_DIR/theme/dock-appicons/browser.png")" != "$browser_sum" ]; then
  echo "FAIL: prefetch must not alter warm PNG bytes on miss" >&2
  fail=1
elif [ ! -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: FORCE=1 must re-resolve even with warm PNGs" >&2
  fail=1
else
  echo "PASS: prefetch FORCE re-resolves and keeps PNGs on miss"
fi

# Disabled → no resolve.
waybar_test_patch_settings '.icons.appicon.enabled = false'
: >"$WAYBAR_TEST_APPICON_LOG"
dis_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" 2>&1
) || true
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: disabled prefetch must not call appicon" >&2
  fail=1
elif ! printf '%s' "$dis_out" | grep -qi 'disabled'; then
  echo "FAIL: disabled prefetch should say so: $dis_out" >&2
  fail=1
else
  echo "PASS: prefetch no-ops when icons.appicon disabled"
fi
waybar_test_patch_settings '.icons.appicon.enabled = true'

# --- launcher cold: offline + miss stamp ---
# Restore fuller dock-apps for launcher (browser entry enough).
cat >"$TEST_DIR/data/dock-apps.json" <<'JSON'
{
  "browser": { "name": "Browser", "appicon": "browser", "icon": "󰈹", "process_names": [] }
}
JSON
rm -f "$TEST_DIR/theme/dock-appicons/browser.png" "$TEST_DIR/theme/dock-appicons/browser"
rm -rf "$CACHE/waybar/appicon-miss"
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
exit 1
EOF
: >"$WAYBAR_TEST_APPICON_LOG"
launcher_cold=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/dock/dock-launcher.sh" browser status
)
if ! grep -q -- '--offline' "$WAYBAR_TEST_APPICON_LOG"; then
  echo "FAIL: launcher cold must use --offline: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
elif [ ! -f "$CACHE/waybar/appicon-miss/browser" ]; then
  echo "FAIL: launcher cold miss should stamp browser" >&2
  fail=1
else
  echo "PASS: launcher cold uses --offline and stamps miss"
fi
: >"$WAYBAR_TEST_APPICON_LOG"
launcher_cold2=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/dock/dock-launcher.sh" browser status
)
if [ -s "$WAYBAR_TEST_APPICON_LOG" ]; then
  echo "FAIL: launcher miss stamp must skip re-resolve" >&2
  fail=1
else
  echo "PASS: launcher miss stamp skips re-resolve"
fi
# Offline hit fills launcher PNG.
write_png "$TEST_DIR/fake-icons/src.png"
export WAYBAR_TEST_APPICON_SRC="$TEST_DIR/fake-icons/src.png"
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
case " $* " in
  *" --offline "*) printf '%s\n' "$WAYBAR_TEST_APPICON_SRC"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
rm -rf "$CACHE/waybar/appicon-miss"
: >"$WAYBAR_TEST_APPICON_LOG"
launcher_fill=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    XDG_CACHE_HOME="$CACHE" WAYBAR_TEST_APPICON_SRC="$TEST_DIR/fake-icons/src.png" \
    "$TEST_DIR/scripts/dock/dock-launcher.sh" browser status
)
waybar_test_assert_jq "$launcher_fill" \
  '(.class | index("appicon")) and (.text == "")' \
  "launcher offline fill: $launcher_fill"
if [ ! -f "$TEST_DIR/theme/dock-appicons/browser.png" ]; then
  echo "FAIL: launcher offline fill must write browser.png" >&2
  fail=1
else
  echo "PASS: launcher offline fill materializes PNG"
fi

# --- unknown window key → dock-win-icons (not launcher) via slot-status ---
cp "$ROOT_DIR/scripts/lib/dock-windows-kde-lib.sh" \
  "$ROOT_DIR/scripts/lib/dock-windows-kde-lib.py" \
  "$ROOT_DIR/scripts/lib/compositor-session.sh" \
  "$ROOT_DIR/scripts/lib/waybar-cache-helpers.sh" \
  "$TEST_DIR/scripts/lib/" 2>/dev/null || true
cp "$ROOT_DIR/scripts/dock/dock-windows-query.sh" "$TEST_DIR/scripts/dock/"
chmod +x "$TEST_DIR/scripts/dock/dock-windows-query.sh" \
  "$TEST_DIR/scripts/lib/dock-windows-kde-lib.sh" \
  "$TEST_DIR/scripts/lib/dock-windows-kde-lib.py"

# Manifest without steam-app key so game is "unknown" for known-key loop.
cat >"$TEST_DIR/data/dock-apps.json" <<'JSON'
{
  "steam": { "name": "Steam", "appicon": "steam", "wm_classes": ["steam"], "icon": "" }
}
JSON
FIXTURE="$ROOT_DIR/scripts/ci/lib/fixtures/windows-runner/golden-dual-steam.txt"
FIXTURE_DATA=$(cat "$FIXTURE")
export WAYBAR_TEST_QDBUS_LOG="$TEST_DIR/qdbus-calls.log"
: >"$WAYBAR_TEST_QDBUS_LOG"
waybar_test_write_bin_stub qdbus6 <<EOF
#!/usr/bin/env sh
echo "\$*" >>"\$WAYBAR_TEST_QDBUS_LOG"
case " \$* " in
  *"org.kde.KWin.activeOutputName"*) printf '%s\n' "DP-1" ;;
  *"org.kde.krunner1.Match"*) cat <<'GOLD'
$FIXTURE_DATA
GOLD
    ;;
  *) exit 0 ;;
esac
EOF
waybar_test_write_bin_stub appicon <<'EOF'
#!/usr/bin/env sh
echo "appicon-called $*" >>"${WAYBAR_TEST_APPICON_LOG:-/dev/null}"
case " $* " in
  *" --offline "*)
    printf '%s\n' "${WAYBAR_TEST_APPICON_SRC}"
    exit 0
    ;;
  *) exit 1 ;;
esac
EOF
rm -f "$TEST_DIR/theme/dock-appicons/steam-app-1891700.png" \
  "$TEST_DIR/theme/dock-win-icons/steam-app-1891700.png"
rm -rf "$CACHE/waybar/appicon-miss"
rm -f "$CACHE/waybar"/dock-windows-list.json "$CACHE/waybar"/dock-windows-list.*.json
mkdir -p "$CACHE/waybar"
: >"$WAYBAR_TEST_APPICON_LOG"
export WAYBAR_COMPOSITOR=kde
game_fill=$(
  WAYBAR_OUTPUT_NAME=DP-1 APPICON_BIN="$TEST_DIR/bin/appicon" PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_TEST_APPICON_SRC="$TEST_DIR/fake-icons/src.png" \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 2 DP-1
)
waybar_test_assert_jq "$game_fill" \
  '(.class | index("appicon-steam-app-1891700")) and (.text == "")' \
  "unknown steam-app offline fill: $game_fill"
if [ -f "$TEST_DIR/theme/dock-appicons/steam-app-1891700.png" ]; then
  echo "FAIL: unknown key must not write dock-appicons/" >&2
  fail=1
elif [ ! -f "$TEST_DIR/theme/dock-win-icons/steam-app-1891700.png" ]; then
  echo "FAIL: unknown key should materialize dock-win-icons/" >&2
  fail=1
elif ! grep -q -- '--offline' "$WAYBAR_TEST_APPICON_LOG"; then
  echo "FAIL: unknown-key fill must be offline: $(cat "$WAYBAR_TEST_APPICON_LOG")" >&2
  fail=1
else
  echo "PASS: unknown window fills dock-win-icons via --offline"
fi

waybar_test_end
