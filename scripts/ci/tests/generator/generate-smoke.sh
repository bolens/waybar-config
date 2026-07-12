#!/usr/bin/env bash
# Default generate smoke + essential file validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "generate-smoke"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed (see generator dump above; try scripts/generate/generate-settings.sh)" >&2
  exit 1
fi
echo "Generator scripts completed successfully."

echo "Validating generated JSONC and CSS files for default settings..."
validate_all_generated_files "default settings" || fail=1

# Positive portability: module configs must keep literal $WAYBAR_HOME (not expanded abs paths)
for port_file in \
  "$TEST_DIR/modules/system.generated.jsonc" \
  "$TEST_DIR/modules/utilities.generated.jsonc" \
  "$TEST_DIR/modules/audio.generated.jsonc"; do
  if [ ! -f "$port_file" ]; then
    echo "FAIL: missing $port_file after default generate" >&2
    fail=1
    continue
  fi
  if ! grep -Fq '$WAYBAR_HOME/scripts' "$port_file"; then
    echo "FAIL: $port_file missing literal \$WAYBAR_HOME/scripts" >&2
    fail=1
  fi
done
echo "PASS: generated modules keep literal \$WAYBAR_HOME/scripts"

# Makefile generate contract (dry-run must include the three entry scripts)
make_n=$(make -C "$ROOT_DIR" -n generate 2>/dev/null || true)
case "$make_n" in
  *generate-settings.sh*generate-compositor-modules.sh*generate-workspaces-css.sh*)
    echo "PASS: make generate dry-run lists settings+compositor+workspaces-css"
    ;;
  *)
    echo "FAIL: make -n generate missing expected scripts: $make_n" >&2
    fail=1
    ;;
esac

# ---------------------------------------------------------------------------
# Contracts for recent reliability / tooltip / SoT work (default real settings)
# ---------------------------------------------------------------------------
waybar_test_end
