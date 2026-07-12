#!/usr/bin/env bash
# Stats carousel hardware group swap + scroll/refresh script contracts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "stats-carousel"
waybar_test_gen_sandbox

echo "Testing stats carousel enabled (default)..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before stats-carousel checks" >&2
  fail=1
fi

# Regression: jq `$hw | index(.)` rebinds `.` to `$hw` and treated every module as a
# metric, collapsing group/hardware to only custom/stats-carousel (wiping drawer,
# nvme, psu, …). Assert exact remaining order + non-metric survivors.
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/hardware".modules
      == [
        "custom/hardware-drawer",
        "custom/stats-carousel",
        "custom/nvme",
        "custom/psu"
      ])
  ' \
  "carousel must replace only cpu/memory/disk/gpu and keep drawer + other telemetry in order"

waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/hardware".modules | length) > 1
    and (."group/hardware".modules != ["custom/stats-carousel"])
    and (."group/hardware".modules | index("custom/cpu") | not)
    and (."group/hardware".modules | index("custom/memory") | not)
    and (."group/hardware".modules | index("custom/disk") | not)
    and (."group/hardware".modules | index("custom/gpu") | not)
  ' \
  "hardware group must not collapse to carousel-only (jq index scoping regression)"

# Generators must use `. as $m | $hw | index($m)` — bare `$hw | index(.)` is the bug.
# Skip comment lines so the explanatory note in generate-settings.sh does not false-positive.
buggy_hits=$(
  grep -nE '\$hw \| index\(\.\)' \
    "$TEST_DIR/scripts/generate/generate-settings.sh" \
    "$TEST_DIR/scripts/generate/generate-drawers-modules.sh" 2>/dev/null \
    | grep -vE ':[[:space:]]*#' \
    || true
)
if [ -n "$buggy_hits" ]; then
  echo "FAIL: apply_stats_carousel still uses buggy \$hw | index(.) (rebinds . to \$hw)" >&2
  printf '%s\n' "$buggy_hits" >&2
  fail=1
fi
if ! grep -q 'as \$m | \$hw | index(\$m)' "$TEST_DIR/scripts/generate/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh apply_stats_carousel missing . as \$m | \$hw | index(\$m)" >&2
  fail=1
fi
if ! grep -q 'as \$m | \$hw | index(\$m)' "$TEST_DIR/scripts/generate/generate-drawers-modules.sh"; then
  echo "FAIL: generate-drawers-modules.sh apply_stats_carousel missing . as \$m | \$hw | index(\$m)" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '."custom/hardware-drawer"."tooltip-format" | test("Stats")' \
  "hardware-drawer tooltip should list Stats when carousel enabled"
# Drawer SoT should still mention non-carousel telemetry (not carousel-only wipe).
waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '
    (."custom/hardware-drawer"."tooltip-format" | test("NVMe|PSU"; "i"))
  ' \
  "hardware-drawer tooltip should still list non-carousel hardware modules"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '
    (."custom/cooling-drawer"."tooltip-format" | test("Fans|CoolerControl|Liquidctl"; "i"))
  ' \
  "cooling-drawer tooltip should list cooling modules"

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
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/stats-carousel"."on-click-middle" | test("--refresh")' \
  "stats-carousel on-click-middle should call --refresh"

if [ ! -x "$TEST_DIR/scripts/system/stats-carousel-status.sh" ]; then
  echo "FAIL: stats-carousel-status.sh missing or not executable" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/system/stats-carousel-status.sh"; then
  echo "FAIL: stats-carousel-status.sh failed bash -n" >&2
  fail=1
fi
if ! grep -q -- '--refresh)' "$TEST_DIR/scripts/system/stats-carousel-status.sh"; then
  echo "FAIL: stats-carousel-status.sh should handle --refresh" >&2
  fail=1
fi
# Peer alignment: cache serve/refresh, gauge_status_text, locale temps, click hints.
for needle in serve_cache_or_refresh gauge_status_text format_locale_temp 'Middle: refresh'; do
  if ! grep -qF -- "$needle" "$TEST_DIR/scripts/system/stats-carousel-status.sh"; then
    echo "FAIL: stats-carousel-status.sh missing peer alignment: $needle" >&2
    fail=1
  fi
done
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/stats-carousel".interval == 8' \
  "stats-carousel interval should match cpu (module_intervals.stats_carousel=8)"

echo "Testing stats carousel disabled..."
waybar_test_patch_settings '.visual.stats_carousel.enabled = false'
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with stats_carousel disabled" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/hardware".modules | index("custom/cpu")) != null
    and (."group/hardware".modules | index("custom/stats-carousel") | not)
  ' \
  "disabled carousel should keep cpu and omit stats-carousel"

# Re-enable for runtime path checks
waybar_test_patch_settings '.visual.stats_carousel.enabled = true'
waybar_test_compile_settings

CAROUSEL_CACHE=$(mktemp -d)
# Stub metrics collector so status path stays offline-friendly.
mkdir -p "$TEST_DIR/scripts/infra"
cat >"$TEST_DIR/scripts/infra/system-metrics-collector.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"cpu":{"usage":42,"temp":50},"memory":{"mem_pct":55,"mem_used_gib":"8.0","mem_total_gib":"16.0"},"gpu":{"available":true,"name":"TestGPU","util":33,"temp":60}}'
EOF
chmod +x "$TEST_DIR/scripts/infra/system-metrics-collector.sh"

# Poll path serves cache (disk-style); cold miss shows placeholder until --refresh.
cold=$(
  XDG_CACHE_HOME="$CAROUSEL_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    "$TEST_DIR/scripts/system/stats-carousel-status.sh"
) || true
waybar_test_assert_jq "$cold" '.tooltip | test("Initializing")' \
  "cold poll should show initializing placeholder: $cold"

# --refresh populates cache (stub signal so CI stays offline).
mkdir -p "$TEST_DIR/scripts/lib"
cat >"$TEST_DIR/scripts/lib/waybar-signal.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_DIR/scripts/lib/waybar-signal.sh"

out=$(
  XDG_CACHE_HOME="$CAROUSEL_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_BACKGROUND=1 \
    "$TEST_DIR/scripts/system/stats-carousel-status.sh" --refresh
) || true
waybar_test_assert_jq "$out" '.text | test("󰍛")' "carousel --refresh default index should show CPU: $out"
waybar_test_assert_jq "$out" '.tooltip | test("Middle: refresh")' \
  "carousel tooltip should include click hints: $out"
waybar_test_assert_jq "$out" '.tooltip | test("Temperature:")' \
  "carousel CPU tooltip should use Temperature label: $out"
if [ ! -f "$CAROUSEL_CACHE/waybar/stats-carousel.json" ]; then
  echo "FAIL: --refresh should write stats-carousel.json cache" >&2
  fail=1
fi

# Poll serves the written cache without recomputing.
served=$(
  XDG_CACHE_HOME="$CAROUSEL_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    "$TEST_DIR/scripts/system/stats-carousel-status.sh"
) || true
waybar_test_assert_jq "$served" '.text | test("󰍛")' "poll should serve cached CPU JSON: $served"

XDG_CACHE_HOME="$CAROUSEL_CACHE" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  "$TEST_DIR/scripts/system/stats-carousel-status.sh" --next >/dev/null 2>&1 || true
out2=$(
  XDG_CACHE_HOME="$CAROUSEL_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    "$TEST_DIR/scripts/system/stats-carousel-status.sh"
) || true
waybar_test_assert_jq "$out2" '.text | test("󰘚")' "carousel --next should advance to memory: $out2"
waybar_test_assert_jq "$out2" '.tooltip | test("Memory:")' \
  "memory slide tooltip should mention Memory: $out2"
rm -rf "$CAROUSEL_CACHE"

echo "PASS: stats carousel"
waybar_test_end
