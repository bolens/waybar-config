#!/usr/bin/env bash
# Lib utility unit tests (emit_waybar_json, cache, strip_jsonc, status smoke).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "lib-utils"
waybar_test_gen_sandbox
if ! waybar_test_gen_default >/dev/null; then
  echo "FAIL: default generate failed before lib-utils" >&2
  exit 1
fi

echo "Testing emit_waybar_json format and escape utility..."
test_json_out=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  emit_waybar_json 'text <&>' 'tooltip\nwith\nnewlines & <tags>' 'myclass'
")

if ! echo "$test_json_out" | jq -e '.text == "text &lt;&amp;&gt;"' >/dev/null 2>&1; then
  echo "FAIL: emit_waybar_json failed to escape text content!" >&2
  echo "Output: $test_json_out" >&2
  fail=1
fi

if ! echo "$test_json_out" | jq -e '.tooltip == "tooltip\nwith\nnewlines &amp; &lt;tags&gt;"' >/dev/null 2>&1; then
  echo "FAIL: emit_waybar_json failed to escape tooltip markup or resolve newlines!" >&2
  echo "Output: $test_json_out" >&2
  fail=1
fi

if ! echo "$test_json_out" | jq -e '.class == "myclass"' >/dev/null 2>&1; then
  echo "FAIL: emit_waybar_json failed to set JSON class!" >&2
  echo "Output: $test_json_out" >&2
  fail=1
fi

# Assert strip_jsonc_comments correctly strips inline/block comments but preserves URLs
echo "Testing strip_jsonc_comments utility..."
cat <<'JSON' >"$TEST_DIR/data/comment-test.jsonc"
/*
 * Block comment here
 */
{
  "url": "https://github.com/bolens", // Inline comment after URL
  // Separate inline comment
  "key": "value" /* block comment on line */
}
JSON

test_stripped=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-settings.sh
  strip_jsonc_comments '$TEST_DIR/data/comment-test.jsonc'
")

if ! echo "$test_stripped" | jq -e '.url == "https://github.com/bolens"' >/dev/null 2>&1; then
  echo "FAIL: strip_jsonc_comments broke URLs or failed to strip inline comment!" >&2
  echo "Output: $test_stripped" >&2
  fail=1
fi

if ! echo "$test_stripped" | jq -e '.key == "value"' >/dev/null 2>&1; then
  echo "FAIL: strip_jsonc_comments failed to strip block comments!" >&2
  echo "Output: $test_stripped" >&2
  fail=1
fi

# Assert cache_file_age works correctly for existing and missing files
echo "Testing cache_file_age utility..."
cache_test_file="$TEST_DIR/data/cache-age-test.json"
echo "test" >"$cache_test_file"

age_fresh=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  cache_file_age '$cache_test_file'
")

if [ "$age_fresh" -lt 0 ] || [ "$age_fresh" -gt 5 ]; then
  echo "FAIL: cache_file_age for fresh file returned incorrect value: $age_fresh" >&2
  fail=1
fi

# Change file modification time to 150 seconds in the past
touch -d "150 seconds ago" "$cache_test_file" 2>/dev/null \
  || touch -m -t "$(date -d "150 seconds ago" +%Y%m%d%H%M.%S)" "$cache_test_file" 2>/dev/null \
  || true

# Recheck age
age_stale=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  cache_file_age '$cache_test_file'
")

# If touch command succeeded, verify value
if [ "$age_stale" -ge 140 ] 2>/dev/null; then
  : # Pass
elif [ "$age_stale" -ge 0 ] 2>/dev/null && [ "$age_stale" -lt 140 ] 2>/dev/null; then
  echo "FAIL: cache_file_age for stale file expected >=140, got $age_stale" >&2
  fail=1
fi

age_missing=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  cache_file_age '$TEST_DIR/data/non-existent-file.json'
")

if [ "$age_missing" -ne 999999 ]; then
  echo "FAIL: cache_file_age for missing file did not return 999999! Value: $age_missing" >&2
  fail=1
fi

# Assert serve_cache_or_refresh works correctly
echo "Testing serve_cache_or_refresh utility..."
echo '{"text":"fresh"}' >"$cache_test_file"
mkdir -p "$TEST_DIR/data/cache-test.lock.d"
serve_out_fresh=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  serve_cache_or_refresh '$cache_test_file' 10 '$TEST_DIR/data/cache-test.lock.d' 20
")
serve_status_fresh=$?
if [ $serve_status_fresh -ne 0 ] || [ "$serve_out_fresh" != '{"text":"fresh"}' ]; then
  echo "FAIL: serve_cache_or_refresh failed on fresh cache! status: $serve_status_fresh, output: $serve_out_fresh" >&2
  fail=1
fi
rmdir "$TEST_DIR/data/cache-test.lock.d"

# Assert get_anim_frame resolves animation sequences correctly
echo "Testing get_anim_frame utility..."
frame_dots_0=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/unicode-animations-lib.sh
  get_anim_frame 'dots' 0
")
frame_dots_10=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/unicode-animations-lib.sh
  get_anim_frame 'dots' 10
")

if [ "$frame_dots_0" != "⠋" ] || [ "$frame_dots_10" != "⠋" ]; then
  echo "FAIL: get_anim_frame dots frame modulo calculation failed! frame_0: $frame_dots_0, frame_10: $frame_dots_10" >&2
  fail=1
fi

# Assert new status scripts output valid JSON and handle missing daemons gracefully
echo "Testing new status scripts execution..."
for script in services/sync/syncthing-status.sh services/apps/sunshine-status.sh services/devices/streamdeck-status.sh services/i2pd/i2pd-status.sh; do
  script_path="$TEST_DIR/scripts/$script"
  out=$(XDG_CACHE_HOME="$TEST_DIR/data" WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" "$script_path" --refresh 2>/dev/null || true)
  if [ -z "$out" ]; then
    echo "FAIL: $script failed to execute or returned empty output" >&2
    fail=1
  elif ! echo "$out" | jq -e '.text != null and .tooltip != null and .class != null' >/dev/null 2>&1; then
    echo "FAIL: $script did not output valid JSON with text, tooltip, and class fields. Output: $out" >&2
    fail=1
  fi
done

# i2pd/settings consumers must keep a bash shebang (regression for Ubuntu dash CI).
for script in services/i2pd/i2pd-status.sh services/sync/updates-status.sh services/apps/github-status.sh; do
  sheb="$(head -1 "$TEST_DIR/scripts/$script" || true)"
  case "$sheb" in
    '#!/usr/bin/env bash' | '#!/bin/bash') ;;
    *)
      echo "FAIL: $script must use bash shebang after sandbox copy (got: $sheb)" >&2
      fail=1
      ;;
  esac
done

# app-open-lib: whitespace split + no glob expand (replaces SC2086 call-site pattern)
echo "Testing waybar_app_open argv splitting..."
APP_OPEN_LOG="$TEST_DIR/app-open-calls.log"
: >"$APP_OPEN_LOG"
cat >"$TEST_DIR/scripts/tools/app-open.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$APP_OPEN_LOG"
EOF
chmod +x "$TEST_DIR/scripts/tools/app-open.sh"

WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" bash -c '
  . "$WAYBAR_SCRIPTS/lib/app-open-lib.sh"
  waybar_app_open "  foo bar  baz  " || exit 1
  # Glob char must stay literal (set -f during split)
  touch "$WAYBAR_HOME/star.txt"
  waybar_app_open "cmd *" || exit 1
  waybar_app_open "" && exit 1
  waybar_app_open "   " && exit 1
  exit 0
' || {
  echo "FAIL: waybar_app_open unit checks failed" >&2
  fail=1
}

if ! grep -Fxq 'foo bar baz' "$APP_OPEN_LOG"; then
  echo "FAIL: waybar_app_open should trim and split. log=$(cat "$APP_OPEN_LOG")" >&2
  fail=1
fi
if ! grep -Fxq 'cmd *' "$APP_OPEN_LOG"; then
  echo "FAIL: waybar_app_open should not glob-expand *. log=$(cat "$APP_OPEN_LOG")" >&2
  fail=1
fi

# Verify behavior when waybar-settings.jsonc is missing
waybar_test_end
