#!/usr/bin/env bash
# compositor-gate show/hide real behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "compositor-gate"

# Host PATH — no polish stubs; exercise real gate script from repo.
# Use HYPRLAND_INSTANCE_SIGNATURE (not WAYBAR_COMPOSITOR) so we exercise session detection.
GATE="$ROOT/scripts/lib/compositor-gate.sh"
rm -f "${SUITE_RUNTIME}/waybar-compositor"
gate_env=(
  env
  -u WAYBAR_COMPOSITOR
  PATH="${PATH}"
  XDG_RUNTIME_DIR="$SUITE_RUNTIME"
  HYPRLAND_INSTANCE_SIGNATURE=test-sig
)
gate_out=$("${gate_env[@]}" "$GATE" --show kde -- echo RAN 2>/dev/null || true)
if ! printf '%s' "$gate_out" | grep -q '"class":"hidden"'; then
  echo "FAIL: compositor-gate --show kde on Hyprland should emit hidden JSON (got: $gate_out)" >&2
  fail=1
fi
gate_run=$("${gate_env[@]}" "$GATE" --show hyprland -- echo RAN 2>/dev/null || true)
if [[ "$gate_run" != "RAN" ]]; then
  echo "FAIL: compositor-gate --show hyprland on Hyprland should exec command (got: $gate_run)" >&2
  fail=1
fi
gate_hide=$("${gate_env[@]}" "$GATE" --hide hyprland -- echo RAN 2>/dev/null || true)
if ! printf '%s' "$gate_hide" | grep -q '"class":"hidden"'; then
  echo "FAIL: compositor-gate --hide hyprland on Hyprland should emit hidden JSON (got: $gate_hide)" >&2
  fail=1
fi
echo "PASS: compositor-gate show/hide"

waybar_test_end
