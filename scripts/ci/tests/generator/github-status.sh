#!/usr/bin/env bash
# GitHub status: notifications preview + review-requested count.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "github-status"
waybar_test_gen_sandbox

echo "Testing github module wiring and review-aware status..."
cp "$ROOT_DIR/scripts/services/apps/github-status.sh" "$TEST_DIR/scripts/services/apps/"
chmod +x "$TEST_DIR/scripts/services/apps/github-status.sh"
# Skip moon/dots animation
cat >"$TEST_DIR/scripts/lib/unicode-animations-lib.sh" <<'EOF'
#!/usr/bin/env sh
animate_command() {
  shift 3
  "$@"
}
EOF

if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before github checks" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/github".exec | test("services/apps/github-status\\.sh$")' \
  "custom/github exec missing github-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/github".signal == 35 and (."custom/github"."on-click-middle" | test("waybar-signal\\.sh github"))' \
  "custom/github should signal on middle refresh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/weather".signal == 34 and (."custom/weather"."on-click-middle" | test("waybar-signal\\.sh weather"))' \
  "custom/weather should signal on middle refresh"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.github.show_reviews == true' \
  "github.show_reviews should default true"

mkdir -p "$TEST_DIR/bin"
cp "$ROOT_DIR/scripts/ci/lib/fixtures/bin-stubs/gh" "$TEST_DIR/bin/gh"
cp "$ROOT_DIR/scripts/ci/lib/fixtures/bin-stubs/timeout" "$TEST_DIR/bin/timeout" 2>/dev/null \
  || waybar_test_write_bin_stub timeout <<'EOF'
#!/usr/bin/env sh
shift
exec "$@"
EOF
chmod +x "$TEST_DIR/bin/"*

out=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$TEST_DIR/gh-cache" \
    WAYBAR_BACKGROUND=1 \
    "$TEST_DIR/scripts/services/apps/github-status.sh" --refresh 2>/dev/null | tail -n 1
)
waybar_test_assert_jq "$out" \
  '(.text | test("5")) and (.text | test("2r")) and (.class == "warning")' \
  "github text should combine 5 notifs + 2r reviews: $out"
waybar_test_assert_jq "$out" \
  '.tooltip | test("Review requests: 2") and test("PRs awaiting review") and test("Notifications: 5")' \
  "github tooltip should include review section: $out"

# show_reviews=false skips search API
waybar_test_compile_settings
jq '.github.show_reviews = false | .github.preview_limit = 3' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"
: >"$TEST_DIR/bin/calls.log"
out2=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$TEST_DIR/gh-cache2" \
    WAYBAR_BACKGROUND=1 \
    "$TEST_DIR/scripts/services/apps/github-status.sh" --refresh 2>/dev/null | tail -n 1
)
waybar_test_assert_jq "$out2" \
  '(.text | test("󰊤 5")) and ((.text | test("2r")) | not)' \
  "show_reviews=false should omit review suffix: $out2"
waybar_test_assert_jq "$out2" \
  '.tooltip | test("and 2 more")' \
  "preview_limit=3 should leave 2 more: $out2"
if grep -q 'search/issues' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: show_reviews=false should not call search/issues. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

waybar_test_end
