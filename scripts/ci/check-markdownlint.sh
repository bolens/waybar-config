#!/usr/bin/env bash
# Lint Markdown with markdownlint-cli2 (package.json / pnpm).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# shellcheck source=ensure-pnpm.sh
. "$ROOT/scripts/ci/ensure-pnpm.sh"

waybar_ci_enable_corepack_pnpm
if [ ! -d node_modules/markdownlint-cli2 ]; then
  echo "Installing pnpm devDependencies..."
  waybar_ci_pnpm_install
fi

echo "=== markdownlint-cli2 ==="
pnpm exec markdownlint-cli2
echo "ok: markdownlint clean"
