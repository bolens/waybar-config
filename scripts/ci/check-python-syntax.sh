#!/usr/bin/env bash
# Syntax-check all Python helpers under scripts/.
set -euo pipefail

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
fail=0

while IFS= read -r -d '' f; do
  echo "Checking $f"
  if ! python3 -m py_compile "$f"; then
    fail=1
  fi
done < <(find "$WAYBAR_HOME/scripts" -type f -name '*.py' -print0 | sort -z)

exit "$fail"
