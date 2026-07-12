#!/usr/bin/env bash
# Stream Deck module: left-click opens UI; click wiring + click helper contracts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "streamdeck-module"
waybar_test_gen_sandbox

click="$TEST_DIR/scripts/services/devices/streamdeck-click.sh"
status="$TEST_DIR/scripts/services/devices/streamdeck-status.sh"

if [ ! -x "$click" ]; then
  echo "FAIL: streamdeck-click.sh missing or not executable" >&2
  fail=1
fi
if ! bash -n "$click"; then
  echo "FAIL: streamdeck-click.sh failed bash -n" >&2
  fail=1
fi
if ! head -1 "$click" | grep -qE 'bash'; then
  echo "FAIL: streamdeck-click.sh must use a bash shebang (sources waybar-settings.sh)" >&2
  fail=1
fi

echo "Testing default generate wires left-click to streamdeck-click.sh open..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before streamdeck checks" >&2
  fail=1
fi
clean_utils=$(waybar_test_read_jsonc "$TEST_DIR/modules/utilities.generated.jsonc")
waybar_test_assert_jq "$clean_utils" \
  '."custom/streamdeck"."on-click" | test("streamdeck-click\\.sh open$")' \
  "streamdeck left-click must open UI via streamdeck-click.sh open"
waybar_test_assert_jq "$clean_utils" \
  '."custom/streamdeck"."on-click-right" | test("streamdeck-click\\.sh restart$")' \
  "streamdeck right-click must restart via streamdeck-click.sh"
waybar_test_assert_jq "$clean_utils" \
  '."custom/streamdeck"."on-click-middle" | test("streamdeck-click\\.sh refresh$")' \
  "streamdeck middle-click must refresh via streamdeck-click.sh"
waybar_test_assert_jq "$clean_utils" \
  '."custom/streamdeck"."on-click" | test("systemctl") | not' \
  "streamdeck left-click must not be a raw systemctl restart"

waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/desk-controls".modules | index("custom/streamdeck") != null' \
  "custom/streamdeck should be in group/desk-controls"

echo "Testing streamdeck-click open launches streamdeck (stubbed)..."
stub=$(mktemp -d)
mkdir -p "$stub"
cat >"$stub/streamdeck" <<'EOF'
#!/bin/sh
printf 'LAUNCHED\n' >"${STREAMDECK_LAUNCHED:?}"
EOF
chmod +x "$stub/streamdeck"
# Force launch path: no existing process, no focus backends, no desktop helpers.
cat >"$stub/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$stub/pgrep"
# Replace app-open with a recorder that execs argv.
cat >"$TEST_DIR/scripts/tools/app-open.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"${STREAMDECK_APP_OPEN_ARGS:?}"
exec "$@"
EOF
chmod +x "$TEST_DIR/scripts/tools/app-open.sh"
# Avoid host compositor focus paths aborting the suite (qdbus/KWin).
cat >"$TEST_DIR/scripts/lib/compositor-session.sh" <<'EOF'
#!/usr/bin/env bash
detect_compositor() { printf 'unknown\n'; }
EOF

launched=$(mktemp)
args_file=$(mktemp)
PATH="$stub:$PATH" \
  STREAMDECK_LAUNCHED="$launched" \
  STREAMDECK_APP_OPEN_ARGS="$args_file" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  XDG_CACHE_HOME="$TEST_DIR/cache" \
  "$click" open >/dev/null 2>&1 || true

if [ ! -s "$launched" ]; then
  echo "FAIL: streamdeck-click open did not launch streamdeck binary" >&2
  fail=1
fi
if ! grep -q 'streamdeck' "$args_file" 2>/dev/null; then
  echo "FAIL: streamdeck-click open did not go through app-open.sh streamdeck (args=$(cat "$args_file" 2>/dev/null))" >&2
  fail=1
fi
# Writable cache log path must be preferred over ~/.streamdeck_ui.log
if ! grep -q 'STREAMDECK_UI_LOG_FILE\|streamdeck-ui.log' "$click"; then
  echo "FAIL: streamdeck-click.sh should set STREAMDECK_UI_LOG_FILE under cache" >&2
  fail=1
fi

rm -rf "$stub" "$launched" "$args_file"

echo "Testing streamdeck-click restart uses .streamdeck.service_name..."
svc_name="app-streamdeck-ui@test-suite.service"
python3 - "$TEST_DIR/data/waybar-settings.jsonc" <<PY
import json, pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
stripped = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
stripped = re.sub(r"(?<!:)//.*", "", stripped)
data = json.loads(stripped)
data.setdefault("streamdeck", {})["service_name"] = "$svc_name"
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
waybar_test_compile_settings

sysctl_stub=$(mktemp -d)
sysctl_log=$(mktemp)
cat >"$sysctl_stub/systemctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"${sysctl_log:?}"
exit 0
EOF
chmod +x "$sysctl_stub/systemctl"
# Avoid real signal/status side effects
cat >"$TEST_DIR/scripts/lib/waybar-signal.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TEST_DIR/scripts/lib/waybar-signal.sh"
cat >"$TEST_DIR/scripts/services/devices/streamdeck-status.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TEST_DIR/scripts/services/devices/streamdeck-status.sh"

PATH="$sysctl_stub:$PATH" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  XDG_CACHE_HOME="$TEST_DIR/cache" \
  "$click" restart >/dev/null 2>&1 || true

if ! grep -qE -- "--user[[:space:]]+restart[[:space:]]+$svc_name" "$sysctl_log" \
  && ! grep -qE "restart[[:space:]]+$svc_name" "$sysctl_log"; then
  echo "FAIL: streamdeck-click restart did not systemctl --user restart $svc_name (log=$(cat "$sysctl_log"))" >&2
  fail=1
else
  echo "PASS: restart uses configured streamdeck.service_name"
fi
rm -rf "$sysctl_stub" "$sysctl_log"

echo "Testing status tooltip documents left=open UI..."
# Re-copy status from source tree — sandbox stub above replaced it.
cp -a "$ROOT_DIR/scripts/services/devices/streamdeck-status.sh" "$status"
if [ -x "$status" ] && ! grep -q 'Left: open UI' "$status"; then
  echo "FAIL: streamdeck-status.sh tooltip should say Left: open UI" >&2
  fail=1
fi

echo "PASS: streamdeck-module"
waybar_test_end
