#!/usr/bin/env bash
# Lint CSS with stylelint (package.json / pnpm).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# shellcheck source=ensure-pnpm.sh
. "$ROOT/scripts/ci/ensure-pnpm.sh"

waybar_ci_enable_corepack_pnpm
if [ ! -d node_modules/stylelint ]; then
  echo "Installing pnpm devDependencies..."
  waybar_ci_pnpm_install
fi

echo "=== stylelint ==="
pnpm exec stylelint \
  "style.css" \
  "theme.css" \
  "theme/**/*.css" \
  "user-style/**/*.css" \
  --ignore-pattern "**/*.generated.css" \
  --ignore-pattern "theme/rofi/**"
echo "ok: stylelint clean"
