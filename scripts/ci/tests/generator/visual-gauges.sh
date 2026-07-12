#!/usr/bin/env bash
# Gauge unicode strips in cpu/memory/disk status when visual.gauges.enabled.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "visual-gauges"
waybar_test_gen_sandbox

# shellcheck source=../../../../scripts/lib/gauge-lib.sh
. "$ROOT_DIR/scripts/lib/gauge-lib.sh"

bar="$(gauge_bar 50 8)"
if [ "${#bar}" -ne 8 ]; then
  echo "FAIL: gauge_bar width expected 8 got ${#bar} ($bar)" >&2
  fail=1
fi
case "$bar" in
  *▁* | *▂* | *▃* | *▄* | *▅* | *▆* | *▇* | *█*) ;;
  *)
    echo "FAIL: gauge_bar missing block chars: $bar" >&2
    fail=1
    ;;
esac

# Force gauges on in sandbox settings and stub metrics path lightly via lib only.
clean=$(waybar_test_read_jsonc "$TEST_DIR/data/waybar-settings.jsonc" 2>/dev/null || true)
if [ -n "$clean" ]; then
  :
fi

# Ensure settings declare visual.gauges
if ! jq -e '.visual.gauges.enabled == true' "$ROOT_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: visual.gauges.enabled should default true in settings" >&2
  fail=1
fi

# Status scripts source gauge-lib when enabled
for script in cpu-status.sh memory-status.sh disk-status.sh; do
  if ! grep -q 'gauge-lib\|gauge_bar' "$ROOT_DIR/scripts/system/$script"; then
    echo "FAIL: $script missing gauge wiring" >&2
    fail=1
  fi
done

waybar_test_end
