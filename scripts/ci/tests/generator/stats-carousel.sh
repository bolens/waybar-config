#!/usr/bin/env bash
# Stats carousel hardware group swap + scroll script contracts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "stats-carousel"
waybar_test_gen_sandbox

echo "Testing stats carousel disabled (default)..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before stats-carousel checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/hardware".modules | index("custom/cpu")) != null
    and (."group/hardware".modules | index("custom/stats-carousel") | not)
  ' \
  "default hardware group should keep cpu and omit stats-carousel"

# Module definition is always emitted for availability.
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/stats-carousel".exec | test("system/stats-carousel-status\\.sh$")' \
  "custom/stats-carousel exec missing"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/stats-carousel"."on-scroll-up" | test("--prev")' \
  "stats-carousel on-scroll-up should call --prev"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/stats-carousel"."on-scroll-down" | test("--next")' \
  "stats-carousel on-scroll-down should call --next"

if [ ! -x "$TEST_DIR/scripts/system/stats-carousel-status.sh" ]; then
  echo "FAIL: stats-carousel-status.sh missing or not executable" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/system/stats-carousel-status.sh"; then
  echo "FAIL: stats-carousel-status.sh failed bash -n" >&2
  fail=1
fi

echo "Testing stats carousel enabled..."
perl -0pi -e 's/"stats_carousel":\s*\{\s*"enabled":\s*false/"stats_carousel": {\n      "enabled": true/' \
  "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_compile_settings
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with stats_carousel enabled" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/hardware".modules | index("custom/stats-carousel")) != null
    and (."group/hardware".modules | index("custom/cpu") | not)
    and (."group/hardware".modules | index("custom/memory") | not)
    and (."group/hardware".modules | index("custom/disk") | not)
    and (."group/hardware".modules | index("custom/gpu") | not)
  ' \
  "enabled carousel should replace cpu/memory/disk/gpu"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '."custom/hardware-drawer"."tooltip-format" | test("Stats")' \
  "hardware-drawer tooltip should list Stats when carousel enabled"

CAROUSEL_CACHE=$(mktemp -d)
# Stub metrics collector so status path stays offline-friendly.
mkdir -p "$TEST_DIR/scripts/infra"
cat >"$TEST_DIR/scripts/infra/system-metrics-collector.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"cpu":{"usage":42,"temp":50},"memory":{"mem_pct":55,"mem_used_gib":"8.0","mem_total_gib":"16.0"},"gpu":{"available":true,"name":"TestGPU","util":33,"temp":60}}'
EOF
chmod +x "$TEST_DIR/scripts/infra/system-metrics-collector.sh"

out=$(
  XDG_CACHE_HOME="$CAROUSEL_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    "$TEST_DIR/scripts/system/stats-carousel-status.sh"
) || true
waybar_test_assert_jq "$out" '.text | test("󰍛")' "carousel default index should show CPU: $out"

XDG_CACHE_HOME="$CAROUSEL_CACHE" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  "$TEST_DIR/scripts/system/stats-carousel-status.sh" --next >/dev/null 2>&1 || true
out2=$(
  XDG_CACHE_HOME="$CAROUSEL_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    "$TEST_DIR/scripts/system/stats-carousel-status.sh"
) || true
waybar_test_assert_jq "$out2" '.text | test("󰘚")' "carousel --next should advance to memory: $out2"
rm -rf "$CAROUSEL_CACHE"

echo "PASS: stats carousel"
waybar_test_end
