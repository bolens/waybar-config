#!/usr/bin/env bash
# Install local git hooks that mirror CI guardrails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_DIR="$ROOT/.git/hooks"
SRC="$ROOT/scripts/ci/pre-commit-check-secrets.sh"

if [ ! -d "$ROOT/.git" ]; then
  echo "FAIL: $ROOT is not a git checkout" >&2
  exit 1
fi
if [ ! -f "$SRC" ]; then
  echo "FAIL: missing $SRC" >&2
  exit 1
fi

mkdir -p "$HOOKS_DIR"
ln -sfn ../../scripts/ci/pre-commit-check-secrets.sh "$HOOKS_DIR/pre-commit"
chmod +x "$SRC"

echo "Installed pre-commit → scripts/ci/pre-commit-check-secrets.sh"
echo "Tip: run \`make check\` before pushing (syntax, suites, drift, lint)."
