#!/usr/bin/env bash
# asusctl module wiring and status/click behavior.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "asusctl"
waybar_test_gen_sandbox

echo "Testing asusctl module wiring and status/click scripts..."
cp "$ROOT_DIR/scripts/system/asusctl-status.sh" "$ROOT_DIR/scripts/system/asusctl-click.sh" "$TEST_DIR/scripts/system/"
chmod +x "$TEST_DIR/scripts/system/asusctl-status.sh" "$TEST_DIR/scripts/system/asusctl-click.sh"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before asusctl checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '."custom/asusctl".exec | test("system/asusctl-status\\.sh$")' "custom/asusctl exec missing asusctl-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '."custom/asusctl".signal == 28' "custom/asusctl signal expected 28"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '."custom/asusctl"."on-scroll-up" | test("asusctl-click\\.sh next")' "custom/asusctl scroll-up should cycle next"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '."custom/asusctl"."on-scroll-down" | test("asusctl-click\\.sh prev")' "custom/asusctl scroll-down should cycle prev"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '."custom/asusctl"."on-click" | test("asusctl-click\\.sh menu")' "custom/asusctl left-click should open profile menu"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" '.["group/desk-controls"].modules | index("custom/asusctl")' "custom/asusctl missing from group/desk-controls"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.module_intervals.asusctl == "once" and .signals.asusctl == 28' "module_intervals/signals.asusctl missing in compiled settings"
if ! bash -n "$TEST_DIR/scripts/system/asusctl-status.sh"; then
  echo "FAIL: asusctl-status.sh failed bash -n" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/system/asusctl-click.sh"; then
  echo "FAIL: asusctl-click.sh failed bash -n" >&2
  fail=1
fi

ASUS_FAKE="$TEST_DIR/fake-asusctl"
ASUS_CACHE="$TEST_DIR/asus-cache"
mkdir -p "$ASUS_FAKE" "$ASUS_CACHE"
ASUS_STATE="$ASUS_FAKE/state"
echo Balanced >"$ASUS_STATE"
cat >"$ASUS_FAKE/asusctl" <<'EOF'
#!/usr/bin/env bash
set -eu
state="${ASUS_STATE_FILE:?}"
cmd="${1:-}"
sub="${2:-}"
case "$cmd" in
  profile)
    case "$sub" in
      get)
        printf 'Active profile is %s\n' "$(cat "$state")"
        ;;
      list)
        printf '%s\n' Quiet Balanced Performance
        ;;
      set)
        printf '%s\n' "${3:?}" >"$state"
        ;;
      next)
        cur=$(cat "$state")
        case "$cur" in
          Quiet) printf 'Balanced\n' >"$state" ;;
          Balanced) printf 'Performance\n' >"$state" ;;
          *) printf 'Quiet\n' >"$state" ;;
        esac
        ;;
      *)
        echo "unknown profile sub: $sub" >&2
        exit 2
        ;;
    esac
    ;;
  battery)
    if [[ "${sub:-}" == "info" ]]; then
      echo "Current charge limit: 80%"
    fi
    ;;
  *)
    echo "unknown: $*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$ASUS_FAKE/asusctl"

asus_out=$(
  WAYBAR_HOME="$TEST_DIR" \
    XDG_CACHE_HOME="$ASUS_CACHE" \
    WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
    ASUS_STATE_FILE="$ASUS_STATE" \
    "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
waybar_test_assert_jq "$asus_out" '.class == "balanced" and (.text | test("Bal")) and (.tooltip | test("Charge limit: 80%"))' "asusctl-status expected balanced + charge limit: $asus_out"

mkdir -p "$TEST_DIR/fakebin"
cat >"$TEST_DIR/fakebin/notify-send" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TEST_DIR/fakebin/notify-send"
PATH="$TEST_DIR/fakebin:/usr/bin:/bin" \
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$ASUS_CACHE" \
  WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
  ASUS_STATE_FILE="$ASUS_STATE" \
  "$TEST_DIR/scripts/system/asusctl-click.sh" next
if [[ "$(cat "$ASUS_STATE")" != "Performance" ]]; then
  echo "FAIL: asusctl-click next from Balanced should set Performance (got $(cat "$ASUS_STATE"))" >&2
  fail=1
fi
asus_perf=$(
  WAYBAR_HOME="$TEST_DIR" \
    XDG_CACHE_HOME="$ASUS_CACHE" \
    WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
    ASUS_STATE_FILE="$ASUS_STATE" \
    "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
waybar_test_assert_jq "$asus_perf" '.class == "performance"' "status after next should be performance: $asus_perf"

PATH="$TEST_DIR/fakebin:/usr/bin:/bin" \
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$ASUS_CACHE" \
  WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
  ASUS_STATE_FILE="$ASUS_STATE" \
  "$TEST_DIR/scripts/system/asusctl-click.sh" prev
if [[ "$(cat "$ASUS_STATE")" != "Balanced" ]]; then
  echo "FAIL: asusctl-click prev from Performance should set Balanced" >&2
  fail=1
fi

asus_miss=$(
  WAYBAR_HOME="$TEST_DIR" \
    XDG_CACHE_HOME="$ASUS_CACHE" \
    WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/missing-asusctl" \
    "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
waybar_test_assert_jq "$asus_miss" '.class == "disconnected" or (.class|tostring|test("disconnected"))' "missing asusctl should emit disconnected: $asus_miss"

cat >"$ASUS_FAKE/asusctl-down2" <<'EOF'
#!/usr/bin/env bash
echo "asusd is not running, start it with systemctl start asusd"
exit 0
EOF
chmod +x "$ASUS_FAKE/asusctl-down2"
asus_down=$(
  WAYBAR_HOME="$TEST_DIR" \
    XDG_CACHE_HOME="$ASUS_CACHE" \
    WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl-down2" \
    "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
waybar_test_assert_jq "$asus_down" '.class == "disconnected" or (.class|tostring|test("disconnected"))' "asusd-down message should emit disconnected: $asus_down"
echo "PASS: asusctl module wiring and status/click behavior"

waybar_test_end
