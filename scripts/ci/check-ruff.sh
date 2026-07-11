#!/usr/bin/env bash
# Lint Python helpers with ruff (config: ruff.toml).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if ! command -v ruff >/dev/null 2>&1; then
  echo "FAIL: ruff not found. Install: https://docs.astral.sh/ruff/installation/" >&2
  exit 1
fi

echo "=== ruff $(ruff --version) ==="
ruff check scripts
echo "ok: ruff clean"
