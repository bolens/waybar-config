#!/usr/bin/env bash
# Homelab health module wiring + empty/targets runtime.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "homelab-status"
waybar_test_gen_sandbox

echo "Testing homelab module wiring and status script..."
mkdir -p "$TEST_DIR/scripts/services/homelab"
cp "$ROOT_DIR/scripts/services/homelab/homelab-status.sh" "$TEST_DIR/scripts/services/homelab/"
cp "$ROOT_DIR/scripts/services/homelab/homelab-click.sh" "$TEST_DIR/scripts/services/homelab/"
chmod +x "$TEST_DIR/scripts/services/homelab/homelab-status.sh" \
  "$TEST_DIR/scripts/services/homelab/homelab-click.sh"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before homelab checks" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/homelab".exec | test("services/homelab/homelab-status\\.sh$")' \
  "custom/homelab exec missing homelab-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/homelab".signal == 33 and ."custom/homelab".interval == 60' \
  "custom/homelab signal/interval expected 33 / 60"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/homelab"."on-click" | test("homelab-status\\.sh --refresh$")' \
  "empty targets on-click should refresh via homelab-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/infra".modules | index("custom/homelab")' \
  "custom/homelab missing from group/infra"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '."custom/infra-drawer"."tooltip-format" | test("Homelab")' \
  "infra-drawer tooltip should list Homelab"

if ! bash -n "$TEST_DIR/scripts/services/homelab/homelab-status.sh"; then
  echo "FAIL: homelab-status.sh failed bash -n" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/services/homelab/homelab-click.sh"; then
  echo "FAIL: homelab-click.sh failed bash -n" >&2
  fail=1
fi

empty=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$TEST_DIR/hl-empty" \
    "$TEST_DIR/scripts/services/homelab/homelab-status.sh" --refresh
)
waybar_test_assert_jq "$empty" \
  '.class == "hidden" and .text == "" and (.tooltip | test("no targets"; "i"))' \
  "empty targets should hide: $empty"

# Configure two targets via compiled settings (inline JSONC comments break naive python strip).
waybar_test_compile_settings
jq '
  .homelab = {
    timeout_sec: 2,
    targets: [
      {name: "Up", url: "http://up.test/ok", expect: "2xx"},
      {name: "Down", url: "http://down.test/fail", expect: "2xx"}
    ]
  }
' "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"

# Re-generate so multi-target click wiring is reflected in modules.
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed after configuring homelab targets" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/homelab"."on-click" | test("homelab-click\\.sh menu$")' \
  "multi-target on-click should use homelab-click.sh menu"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '."custom/homelab"."on-click-right" | test("homelab-click\\.sh open-first$")' \
  "multi-target on-click-right should use homelab-click.sh open-first"

mkdir -p "$TEST_DIR/bin"
waybar_test_write_bin_stub curl <<'EOF'
#!/usr/bin/env sh
# Last non-flag arg is URL for our status script invocations.
url=""
for a in "$@"; do
  case "$a" in
    http*|https*) url=$a ;;
  esac
done
case "$url" in
  *up.test*) printf '200' ;;
  *down.test*) printf '503' ;;
  *) printf '000' ;;
esac
EOF

mixed=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$TEST_DIR/hl-mixed" \
    "$TEST_DIR/scripts/services/homelab/homelab-status.sh" --refresh
)
waybar_test_assert_jq "$mixed" \
  '.class == "warning" and (.text | test("1/2")) and (.tooltip | test("Up")) and (.tooltip | test("Down")) and (.tooltip | test("pick target"))' \
  "mixed targets expected warning 1/2 with pick-target hint: $mixed"

# All up → normal
jq '
  .homelab.targets = [
    {name: "A", url: "http://up.test/a", expect: "2xx"},
    {name: "B", url: "http://up.test/b", expect: "2xx"}
  ]
' "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"
ok=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$TEST_DIR/hl-ok" \
    "$TEST_DIR/scripts/services/homelab/homelab-status.sh" --refresh
)
waybar_test_assert_jq "$ok" '.class == "normal" and (.text | test("2/2"))' "all up expected normal 2/2: $ok"

echo "Testing homelab-click open-first / refresh / empty menu..."
mkdir -p "$TEST_DIR/scripts/services/homelab" "$TEST_DIR/scripts/tools" "$TEST_DIR/scripts/lib"
cp -f "$ROOT_DIR/scripts/services/homelab/homelab-click.sh" "$TEST_DIR/scripts/services/homelab/"
cp -f "$ROOT_DIR/scripts/lib/rofi-popup-lib.sh" "$TEST_DIR/scripts/lib/" 2>/dev/null || true
cp -f "$ROOT_DIR/scripts/lib/waybar-signal.sh" "$TEST_DIR/scripts/lib/" 2>/dev/null || true
chmod +x "$TEST_DIR/scripts/services/homelab/homelab-click.sh"

cat >"$TEST_DIR/scripts/tools/app-open.sh" <<'EOF'
#!/usr/bin/env sh
# Record opened URL for assertions (last arg).
printf '%s\n' "$*" >"${WAYBAR_HOME}/.homelab-open"
EOF
chmod +x "$TEST_DIR/scripts/tools/app-open.sh"

rm -f "$TEST_DIR/.homelab-open"
PATH="$TEST_DIR/bin:$PATH" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$TEST_DIR/hl-click" \
  bash "$TEST_DIR/scripts/services/homelab/homelab-click.sh" open-first
if [ ! -f "$TEST_DIR/.homelab-open" ] || ! grep -q 'http://up.test/a' "$TEST_DIR/.homelab-open"; then
  echo "FAIL: open-first should open first target URL via app-open: $(cat "$TEST_DIR/.homelab-open" 2>/dev/null || echo missing)" >&2
  fail=1
else
  echo "PASS: open-first opened first URL"
fi

# refresh should not open a URL
rm -f "$TEST_DIR/.homelab-open"
PATH="$TEST_DIR/bin:$PATH" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$TEST_DIR/hl-refresh" \
  bash "$TEST_DIR/scripts/services/homelab/homelab-click.sh" refresh
if [ -f "$TEST_DIR/.homelab-open" ]; then
  echo "FAIL: refresh must not open a URL" >&2
  fail=1
else
  echo "PASS: refresh did not open URL"
fi

# empty targets → menu exits quietly
jq '.homelab.targets = []' "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"
rm -f "$TEST_DIR/.homelab-open"
if ! PATH="$TEST_DIR/bin:$PATH" \
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/services/homelab/homelab-click.sh" menu; then
  echo "FAIL: menu with empty targets should exit 0" >&2
  fail=1
elif [ -f "$TEST_DIR/.homelab-open" ]; then
  echo "FAIL: empty menu should not open URL" >&2
  fail=1
else
  echo "PASS: empty targets menu is a no-op"
fi

if ! bash -n "$TEST_DIR/scripts/services/homelab/homelab-click.sh"; then
  echo "FAIL: homelab-click.sh bash -n" >&2
  fail=1
fi

waybar_test_end
