#!/usr/bin/env bash
# Drawer/group CSS SoT: settings drawers.icons ↔ lib ↔ generated layout/colors.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "drawer-group-css-contracts"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed" >&2
  exit 1
fi

. "$TEST_DIR/scripts/lib/css-selectors-lib.sh"

settings="$TEST_DIR/data/waybar-settings.json"
drawers_css="$TEST_DIR/theme/drawers.generated.css"
groups_css="$TEST_DIR/theme/groups.generated.css"
semantic="$TEST_DIR/theme/semantic-colors.generated.css"
fail=0

echo "Testing drawers.icons keys ⊆ lib drawer sides..."
mapfile -t icon_keys < <(jq -r '.drawers.icons | keys[]' "$settings" | sort)
mapfile -t lib_sides < <(waybar_css_drawer_sides | sort)
for key in "${icon_keys[@]}"; do
  if ! printf '%s\n' "${lib_sides[@]}" | grep -Fxq "$key"; then
    echo "FAIL: drawers.icons.$key missing from waybar_css_drawer_sides" >&2
    fail=1
  fi
done
for side in "${lib_sides[@]}"; do
  if ! printf '%s\n' "${icon_keys[@]}" | grep -Fxq "$side"; then
    echo "FAIL: lib side $side missing from drawers.icons (settings SoT)" >&2
    fail=1
  fi
done

echo "Testing drawer handles in drawers.generated.css + semantic colors..."
while IFS= read -r id; do
  [ -z "$id" ] && continue
  if ! grep -Fq "$id" "$drawers_css"; then
    echo "FAIL: $id missing from drawers.generated.css" >&2
    fail=1
  fi
  if ! grep -Fq "$id" "$semantic"; then
    echo "FAIL: $id missing from semantic-colors.generated.css" >&2
    fail=1
  fi
done < <(waybar_css_drawer_handle_ids)

echo "Testing drawer group shells in drawers.generated.css..."
while IFS= read -r id; do
  [ -z "$id" ] && continue
  if ! grep -Fq "$id" "$drawers_css"; then
    echo "FAIL: $id missing from drawers.generated.css" >&2
    fail=1
  fi
done < <(waybar_css_drawer_group_shell_ids)

echo "Testing cluster groups in groups.generated.css + semantic..."
while IFS= read -r id; do
  [ -z "$id" ] && continue
  if ! grep -Fq "$id" "$groups_css"; then
    echo "FAIL: $id missing from groups.generated.css" >&2
    fail=1
  fi
  if ! grep -Fq "$id" "$semantic"; then
    echo "FAIL: $id missing from semantic-colors.generated.css" >&2
    fail=1
  fi
done < <(waybar_css_cluster_group_ids)

echo "Testing theme.css imports generated drawer/group CSS..."
if ! grep -q 'theme/drawers.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css must import theme/drawers.generated.css" >&2
  fail=1
fi
if ! grep -q 'theme/groups.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css must import theme/groups.generated.css" >&2
  fail=1
fi
if grep -q 'theme/drawers.css"' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css must not import hand theme/drawers.css (use generated)" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "PASS: drawer-group-css-contracts"
waybar_test_end
