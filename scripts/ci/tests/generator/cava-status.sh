#!/usr/bin/env bash
# Cava visualizer module wiring + missing/present runtime.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "cava-status"
waybar_test_gen_sandbox

echo "Testing cava module wiring and status script..."
cp "$ROOT_DIR/scripts/media/cava-status.sh" "$TEST_DIR/scripts/media/"
chmod +x "$TEST_DIR/scripts/media/cava-status.sh"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before cava checks" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  '."custom/cava".exec | test("media/cava-status\\.sh$")' \
  "custom/cava exec missing cava-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  '."custom/cava"."restart-interval" == 2 and ."custom/cava"."hide-empty-text" == true' \
  "custom/cava should use restart-interval + hide-empty-text"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/media".modules | (index("custom/cava") != null or ((. // []) | type == "array"))' \
  "group/media should exist"
# When host SoT disables cava, module wiring may still define custom/cava but group omits it.
if jq -e '.cava.enabled == false' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
    '(."group/media".modules | index("custom/cava")) == null' \
    "cava.enabled=false: custom/cava absent from group/media"
else
  waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
    '."group/media".modules | index("custom/cava")' \
    "custom/cava missing from group/media"
  waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
    '."custom/media-drawer"."tooltip-format" | test("Visualizer")' \
    "media-drawer tooltip should list Visualizer"
fi

if ! bash -n "$TEST_DIR/scripts/media/cava-status.sh"; then
  echo "FAIL: cava-status.sh failed bash -n" >&2
  fail=1
fi

# Missing cava → first JSON line is hidden (WAYBAR_CAVA_BIN points at a missing binary).
missing=$(
  PATH="$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_CAVA_BIN="/nonexistent/cava-missing-$$" \
    timeout 2 "$TEST_DIR/scripts/media/cava-status.sh" 2>/dev/null | head -n 1 || true
)
waybar_test_assert_jq "$missing" \
  '.class == "hidden" and .text == "" and (.tooltip | test("Install cava"))' \
  "missing cava should emit hidden: $missing"

# Fake cava writes one ascii frame to the fifo from its config.
mkdir -p "$TEST_DIR/bin"
waybar_test_write_bin_stub cava <<'EOF'
#!/usr/bin/env bash
set -eu
cfg=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p)
      cfg="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[ -n "$cfg" ] || exit 1
target=$(awk -F'= *' '/raw_target/ {gsub(/ /,"",$2); print $2; exit}' "$cfg")
[ -n "$target" ] || exit 1
# Writer opens FIFO so the status script's reader unblocks.
exec 3>"$target"
printf '7;6;5;4;3;2;1;0\n' >&3
sleep 5
EOF

present=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_CAVA_BIN="$TEST_DIR/bin/cava" \
    timeout 3 "$TEST_DIR/scripts/media/cava-status.sh" 2>/dev/null | head -n 1 || true
)
waybar_test_assert_jq "$present" \
  '.class == "normal" and (.text | test("█"))' \
  "fake cava frame should emit bars: $present"

waybar_test_end
