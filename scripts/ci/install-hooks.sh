#!/usr/bin/env bash
# Install local git hooks that mirror CI guardrails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_DIR="$ROOT/.git/hooks"
PRE_COMMIT="$ROOT/scripts/ci/pre-commit"
PRE_PUSH="$ROOT/scripts/ci/pre-push"

if [ ! -e "$ROOT/.git" ]; then
  echo "FAIL: $ROOT is not a git checkout" >&2
  exit 1
fi
mkdir -p "$HOOKS_DIR"
ln -sfn ../../scripts/ci/pre-commit "$HOOKS_DIR/pre-commit"
ln -sfn ../../scripts/ci/pre-push "$HOOKS_DIR/pre-push"
chmod +x "$PRE_COMMIT" "$PRE_PUSH" scripts/ci/pre-commit-check-secrets.sh

echo "Installed pre-commit and pre-push hooks from scripts/ci/."
