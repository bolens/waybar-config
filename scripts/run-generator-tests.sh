#!/usr/bin/env bash
# Integrated unit and behavior tests for Waybar configuration generators.
set -euo pipefail

echo "=== Running Waybar Configuration Generator Tests ==="

# 1. Create a sandboxed WAYBAR_HOME directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Created sandboxed test directory: $TEST_DIR"

# 2. Populate the sandboxed directory with templates, data, and script files
mkdir -p "$TEST_DIR/data" "$TEST_DIR/layouts" "$TEST_DIR/includes" "$TEST_DIR/modules" "$TEST_DIR/theme"

cp -r data/* "$TEST_DIR/data/"
cp layouts/*.jsonc "$TEST_DIR/layouts/"
cp includes/*.jsonc "$TEST_DIR/includes/"
cp modules/workspaces.jsonc "$TEST_DIR/modules/"
cp -r scripts "$TEST_DIR/scripts"

# Make sure the copied scripts are executable
chmod +x "$TEST_DIR"/scripts/*.sh "$TEST_DIR"/scripts/*.py

# 3. Export the custom WAYBAR_HOME environment variable to test behavior path independence
export WAYBAR_HOME="$TEST_DIR"
export WAYBAR_SCRIPTS="$TEST_DIR/scripts"

echo "Running configuration generator scripts under WAYBAR_HOME=$WAYBAR_HOME..."

# Run the settings and module generator scripts
if ! "$TEST_DIR/scripts/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh exited with non-zero code" >&2
  exit 1
fi

if ! "$TEST_DIR/scripts/generate-compositor-modules.sh"; then
  echo "FAIL: generate-compositor-modules.sh exited with non-zero code" >&2
  exit 1
fi

if ! "$TEST_DIR/scripts/generate-workspaces-css.sh"; then
  echo "FAIL: generate-workspaces-css.sh exited with non-zero code" >&2
  exit 1
fi

echo "Generator scripts completed successfully."

# 4. Run syntax and contents checks on the generated outputs
fail=0

strip_jsonc() {
  python3 - "$1" <<'PY'
import json, re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
    json.loads(text)
except Exception as e:
    sys.stderr.write(f"JSON Parse Error: {e}\n")
    sys.exit(1)
PY
}

echo "Validating generated JSONC files..."

# Ensure we have generated files
generated_files=()
while IFS=  read -r -d $'\0'; do
    generated_files+=("$REPLY")
done < <(find "$TEST_DIR" -name "*.generated.jsonc" -print0)

if [ ${#generated_files[@]} -eq 0 ]; then
  echo "FAIL: No generated JSONC files were found!" >&2
  fail=1
fi

for file in "${generated_files[@]}"; do
  # Check if it parses as valid JSON
  if ! strip_jsonc "$file" 2>/dev/null; then
    echo "FAIL: JSON syntax error in $file" >&2
    fail=1
    continue
  fi

  # Check that it DOES NOT contain any hardcoded references to /home/ or ~/.config/waybar
  if grep -E "/home/|~/\.config/waybar" "$file" >/dev/null 2>&1; then
    echo "FAIL: Hardcoded path detected in $file" >&2
    grep -n -E "/home/|~/\.config/waybar" "$file" >&2
    fail=1
  fi
done

# Check the generated CSS file too
css_file="$TEST_DIR/theme/workspaces.generated.css"
if [ ! -f "$css_file" ]; then
  echo "FAIL: workspaces.generated.css was not created!" >&2
  fail=1
else
  if grep -E "/home/|~/\.config/waybar" "$css_file" >/dev/null 2>&1; then
    echo "FAIL: Hardcoded path detected in $css_file" >&2
    fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: All generated configuration files are syntactically valid and free of hardcoded user paths."
else
  echo "FAIL: One or more validations failed!" >&2
  exit 1
fi

exit 0
