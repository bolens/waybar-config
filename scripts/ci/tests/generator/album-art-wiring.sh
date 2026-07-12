#!/usr/bin/env bash
# Album art module wiring, generated CSS, gitignore, and cover-cache cleanup.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "album-art-wiring"
waybar_test_gen_sandbox

art_css="$TEST_DIR/theme/album-art.generated.css"

echo "Testing album art disabled..."
# Hermetic: force-disable regardless of SoT default.
waybar_test_patch_settings '.visual.album_art.enabled = false'
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before album-art checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  'has("custom/album-art") | not' \
  "custom/album-art should be absent when visual.album_art.enabled=false"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/media".modules | index("custom/album-art") | not' \
  "album-art should not appear in group/media when disabled"
if [ ! -f "$art_css" ]; then
  echo "FAIL: album-art.generated.css missing when album_art disabled" >&2
  fail=1
elif ! grep -q 'visual.album_art disabled' "$art_css"; then
  echo "FAIL: disabled album-art.generated.css should be a stub" >&2
  fail=1
fi

if [ ! -x "$TEST_DIR/scripts/media/album-art-status.sh" ]; then
  echo "FAIL: album-art-status.sh missing or not executable" >&2
  fail=1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/media/album-art-status.sh" \
  "album-art-status.sh failed bash -n"

echo "Testing album art enabled..."
waybar_test_patch_settings '.visual.album_art.enabled = true | .visual.album_art.size = 28'
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with album_art enabled" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  '."custom/album-art"."hide-empty-text" == true' \
  "custom/album-art should set hide-empty-text"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  '."custom/album-art".exec | test("media/album-art-status\\.sh$")' \
  "custom/album-art exec should point at album-art-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/media".modules | index("custom/album-art")) as $a
    | (."group/media".modules | index("custom/mpris")) as $m
    | ($a != null) and ($m != null) and ($a < $m)
  ' \
  "album-art should be inserted before mpris in group/media"

if [ ! -f "$art_css" ]; then
  echo "FAIL: album-art.generated.css missing when album_art enabled" >&2
  fail=1
else
  if ! grep -q 'min-width: 28px' "$art_css" || ! grep -q 'min-height: 28px' "$art_css"; then
    echo "FAIL: album-art.generated.css should use visual.album_art.size" >&2
    fail=1
  fi
  if ! grep -q 'url("album-art")' "$art_css"; then
    echo "FAIL: album-art.generated.css should use relative url(\"album-art\")" >&2
    fail=1
  fi
fi

if ! grep -q 'theme/album-art.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css must import theme/album-art.generated.css" >&2
  fail=1
fi

echo "Testing gitignore keeps album-art.generated.css trackable..."
# --no-index: evaluate ignore rules even though the path is tracked in the repo.
if git -C "$ROOT_DIR" check-ignore -q --no-index theme/album-art.generated.css; then
  echo "FAIL: theme/album-art.generated.css must NOT be gitignored" >&2
  fail=1
fi
if ! git -C "$ROOT_DIR" check-ignore -q --no-index theme/album-art.png; then
  echo "FAIL: theme/album-art.png (runtime cover) must be gitignored" >&2
  fail=1
fi
if ! git -C "$ROOT_DIR" check-ignore -q --no-index theme/album-art; then
  echo "FAIL: theme/album-art (runtime cover symlink) must be gitignored" >&2
  fail=1
fi

echo "Testing status hide + cover cleanup without deleting generated CSS..."
ART_CACHE=$(mktemp -d)
STUB_BIN=$(mktemp -d)
# Hermetic: never talk to the host's real MPRIS players via playerctl.
cat >"$STUB_BIN/playerctl" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_BIN/playerctl"
hidden=$(
  XDG_CACHE_HOME="$ART_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    PATH="$STUB_BIN:/usr/bin:/bin" \
    "$TEST_DIR/scripts/media/album-art-status.sh" 2>/dev/null || true
)
waybar_test_assert_jq "$hidden" \
  '.class == "hidden" and .text == ""' \
  "album-art without playerctl/player should hide: $hidden"

# Regression: no-player cleanup must not delete album-art.generated.css.
printf '%s\n' '/* probe-no-player */' >"$art_css"
printf 'x' >"$TEST_DIR/theme/album-art.png"
ln -sfn "$TEST_DIR/theme/album-art.png" "$TEST_DIR/theme/album-art"
XDG_CACHE_HOME="$ART_CACHE" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  PATH="$STUB_BIN:/usr/bin:/bin" \
  "$TEST_DIR/scripts/media/album-art-status.sh" >/dev/null 2>&1 || true
if [ ! -f "$art_css" ]; then
  echo "FAIL: no-player cleanup deleted album-art.generated.css" >&2
  fail=1
elif ! grep -q 'probe-no-player' "$art_css"; then
  echo "FAIL: no-player cleanup replaced album-art.generated.css" >&2
  fail=1
fi
if [ -e "$TEST_DIR/theme/album-art" ] || [ -e "$TEST_DIR/theme/album-art.png" ]; then
  echo "FAIL: no-player cleanup left cover cache behind" >&2
  fail=1
fi

# Regression: empty artUrl cleanup path (player present, no cover).
cat >"$STUB_BIN/playerctl" <<'EOF'
#!/bin/sh
case "$1" in
  status) exit 0 ;;
  metadata)
    case "${2:-}" in
      mpris:artUrl) exit 0 ;;
      --format) printf '%s\n' "Track"; exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$STUB_BIN/playerctl"
printf '%s\n' '/* probe-empty-art */' >"$art_css"
printf 'x' >"$TEST_DIR/theme/album-art.jpg"
ln -sfn "$TEST_DIR/theme/album-art.jpg" "$TEST_DIR/theme/album-art"
XDG_CACHE_HOME="$ART_CACHE" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  PATH="$STUB_BIN:/usr/bin:/bin" \
  "$TEST_DIR/scripts/media/album-art-status.sh" >/dev/null 2>&1 || true
if [ ! -f "$art_css" ]; then
  echo "FAIL: empty-artUrl cleanup deleted album-art.generated.css" >&2
  fail=1
elif ! grep -q 'probe-empty-art' "$art_css"; then
  echo "FAIL: empty-artUrl cleanup replaced album-art.generated.css" >&2
  fail=1
fi
if [ -e "$TEST_DIR/theme/album-art" ] || [ -e "$TEST_DIR/theme/album-art.jpg" ]; then
  echo "FAIL: empty-artUrl cleanup left cover cache behind" >&2
  fail=1
fi
rm -rf "$ART_CACHE" "$STUB_BIN"

echo "PASS: album art wiring"
waybar_test_end
