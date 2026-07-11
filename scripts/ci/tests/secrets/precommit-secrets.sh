#!/usr/bin/env bash
# pre-commit-check-secrets syntax + behavioral blocks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "precommit-secrets"
waybar_test_secrets_sandbox

# --- pre-commit helper: syntax + behavioral blocks ---
if ! bash -n "$ROOT/scripts/ci/pre-commit-check-secrets.sh"; then
  echo "FAIL: pre-commit-check-secrets.sh syntax error" >&2
  fail=1
else
  echo "PASS: pre-commit-check-secrets.sh syntax"
fi

HOOK_REPO=$(mktemp -d)
(
  set -e
  cd "$HOOK_REPO"
  git init -q
  git config user.email "ci@waybar.test"
  git config user.name "waybar-ci"
  mkdir -p data scripts/ci
  cp "$ROOT/scripts/ci/pre-commit-check-secrets.sh" scripts/ci/
  chmod +x scripts/ci/pre-commit-check-secrets.sh
  printf '{}\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  git commit -q -m init
  # Block secrets filename
  printf '{}\n' >data/waybar-secrets.jsonc
  git add -f data/waybar-secrets.jsonc
  if scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should block staged waybar-secrets.jsonc" >&2
    exit 1
  fi
  git reset -q HEAD -- data/waybar-secrets.jsonc
  rm -f data/waybar-secrets.jsonc
  # Block console_pass in settings
  printf '{\n  "services": { "i2pd": { "console_pass": "leak" } }\n}\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  if scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should block console_pass in settings" >&2
    exit 1
  fi
  # Block coolercontrol ui_pass in settings
  printf '{\n  "services": { "coolercontrol": { "ui_pass": "leak" } }\n}\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  if scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should block ui_pass in settings" >&2
    exit 1
  fi
  # Clean stage OK
  printf '{ "bars": { "layer": "overlay" } }\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  if ! scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should allow clean settings" >&2
    exit 1
  fi
  echo "PASS: pre-commit behavioral blocks"
) || fail=1
rm -rf "$HOOK_REPO"

waybar_test_end
