#!/usr/bin/env bash
# Pill ID SoT contract: css-selectors-lib.sh ↔ module-pills + semantic CSS.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "pill-css-contracts"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed" >&2
  exit 1
fi

. "$TEST_DIR/scripts/lib/css-selectors-lib.sh"

pills="$TEST_DIR/theme/module-pills.generated.css"
semantic="$TEST_DIR/theme/semantic-colors.generated.css"
fail=0

echo "Testing every waybar_css_pill_ids entry appears in generated CSS..."
while IFS= read -r id; do
  [ -z "$id" ] && continue
  if ! grep -Fq "$id" "$pills"; then
    echo "FAIL: $id missing from module-pills.generated.css" >&2
    fail=1
  fi
  if ! grep -Fq "$id" "$semantic"; then
    echo "FAIL: $id missing from semantic-colors.generated.css" >&2
    fail=1
  fi
done < <(waybar_css_pill_ids)

echo "Testing dead #idle-inhibitor spelling is absent..."
if grep -Fq '#idle-inhibitor' "$pills" "$semantic"; then
  echo "FAIL: use #idle_inhibitor (Waybar widget id), not #idle-inhibitor" >&2
  fail=1
fi
if ! grep -Fq '#idle_inhibitor' "$pills" || ! grep -Fq '#idle_inhibitor' "$semantic"; then
  echo "FAIL: #idle_inhibitor must appear in pill + semantic CSS" >&2
  fail=1
fi

echo "Testing hover SoT excludes power specialty modules..."
if waybar_css_pill_hover_ids | grep -Eq '^#custom-(lock|power-menu|logout|suspend|reboot|shutdown)$'; then
  echo "FAIL: power specialty IDs must not be in pill hover SoT" >&2
  fail=1
fi
if ! waybar_css_pill_hover_ids | grep -Fxq '#submap'; then
  echo "FAIL: #submap must be in pill hover SoT" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "PASS: pill-css-contracts"
waybar_test_end
