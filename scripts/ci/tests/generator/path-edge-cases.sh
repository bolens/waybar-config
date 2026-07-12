#!/usr/bin/env bash
# Path-with-spaces, Hyprland without hyprland.jsonc, flat script path validate.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "path-edge-cases"

echo "Verifying resilience to spaces in directory name..."
SPACE_DIR_PARENT=$(waybar_test_mktemp)
SPACE_DIR="$SPACE_DIR_PARENT/waybar test space"
waybar_test_populate_tree "$SPACE_DIR"

if ! WAYBAR_HOME="$SPACE_DIR" WAYBAR_SCRIPTS="$SPACE_DIR/scripts" "$SPACE_DIR/scripts/generate/generate-settings.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-settings.sh failed when run inside a directory with spaces!" >&2
  fail=1
else
  echo "PASS: generate-settings.sh succeeded with spaces in directory name."
fi

echo "Verifying Hyprland generate without modules/hyprland.jsonc..."
# Desk-hypr group must self-heal without a stub hyprland.jsonc file.
HYPR_DIR=$(waybar_test_mktemp)
waybar_test_populate_tree "$HYPR_DIR"
WAYBAR_HOME="$HYPR_DIR" WAYBAR_SCRIPTS="$HYPR_DIR/scripts" \
  "$HYPR_DIR/scripts/generate/generate-settings.sh" >/dev/null 2>&1 || true
rm -f "$HYPR_DIR/modules/hyprland.jsonc"
if ! HYPRLAND_INSTANCE_SIGNATURE=test-sig \
  WAYBAR_HOME="$HYPR_DIR" WAYBAR_SCRIPTS="$HYPR_DIR/scripts" \
  "$HYPR_DIR/scripts/generate/generate-compositor-modules.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-compositor-modules.sh failed on Hyprland without hyprland.jsonc" >&2
  fail=1
else
  hypr_mods=$(python3 -c "
import json, re
t=open('$HYPR_DIR/modules/groups-desk-hypr.generated.jsonc').read()
t=re.sub(r'/\*.*?\*/', '', t, flags=re.S)
t=re.sub(r'^\s*//.*$', '', t, flags=re.M)
print(','.join(json.loads(t)['group/desk-hypr']['modules']))
")
  case "$hypr_mods" in
    *custom/ws-0*hyprland/submap*custom/hyprlight*custom/hyprwhspr*)
      echo "PASS: Hyprland desk group keeps slots + hypr_tail without hyprland.jsonc"
      ;;
    *)
      echo "FAIL: Hyprland desk group missing slots/tail without hyprland.jsonc: $hypr_mods" >&2
      fail=1
      ;;
  esac
fi

echo "Verifying validate rejects flat script paths..."
# Domain subdirs required (scripts/system/…); flat scripts/cpu-status.sh is invalid.
FLAT_DIR=$(waybar_test_mktemp)
mkdir -p "$FLAT_DIR/modules" "$FLAT_DIR/includes" "$FLAT_DIR/layouts" "$FLAT_DIR/data" "$FLAT_DIR/scripts/ci"
cp "$ROOT_DIR/scripts/ci/validate-generated-config.sh" "$FLAT_DIR/scripts/ci/"
printf '{}\n' >"$FLAT_DIR/data/waybar-settings.json"
printf '{}\n' >"$FLAT_DIR/modules/workspaces.generated.jsonc"
cat >"$FLAT_DIR/modules/system.generated.jsonc" <<'JSON'
{
  "custom/cpu": {
    "exec": "$WAYBAR_HOME/scripts/cpu-status.sh"
  }
}
JSON
if WAYBAR_HOME="$FLAT_DIR" "$FLAT_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject flat \$WAYBAR_HOME/scripts/cpu-status.sh" >&2
  fail=1
else
  echo "PASS: validate rejects flat scripts/<file> paths"
fi
mkdir -p "$FLAT_DIR/scripts/system"
cat >"$FLAT_DIR/modules/system.generated.jsonc" <<'JSON'
{
  "custom/cpu": {
    "exec": "$WAYBAR_HOME/scripts/system/cpu-status.sh"
  }
}
JSON
if WAYBAR_HOME="$FLAT_DIR" "$FLAT_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject missing scripts/system/cpu-status.sh" >&2
  fail=1
else
  echo "PASS: validate rejects missing resolved script paths"
fi

waybar_test_end
