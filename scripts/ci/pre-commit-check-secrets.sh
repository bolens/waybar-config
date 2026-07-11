#!/usr/bin/env sh
# Block committing local secrets or credential values in tracked settings.
set -eu

blocked=0

if git diff --cached --name-only --diff-filter=ACM \
  | grep -v 'waybar-secrets\.example\.jsonc' \
  | grep -E '(^|/)waybar-secrets\.jsonc?$' >/dev/null 2>&1; then
  echo "pre-commit: refusing to commit data/waybar-secrets.json(c) — keep secrets local" >&2
  blocked=1
fi

# Credential keys must not appear with a real value in tracked settings
if git diff --cached -U0 -- data/waybar-settings.jsonc data/waybar-settings.json 2>/dev/null \
  | grep -E '^\+.*"(console_pass|ui_pass)"[[:space:]]*:[[:space:]]*"[^"]+"' >/dev/null 2>&1; then
  echo "pre-commit: refusing console_pass/ui_pass in waybar-settings — use data/waybar-secrets.jsonc" >&2
  blocked=1
fi
# CoolerControl bearer token (services.coolercontrol.token only)
if git diff --cached -U0 -- data/waybar-settings.jsonc data/waybar-settings.json 2>/dev/null \
  | grep -E '^\+.*"coolercontrol"[^}]*"token"[[:space:]]*:[[:space:]]*"[^"]+"|^\+[[:space:]]*"token"[[:space:]]*:[[:space:]]*"cc_[^"]+"' >/dev/null 2>&1; then
  echo "pre-commit: refusing coolercontrol token in waybar-settings — use data/waybar-secrets.jsonc" >&2
  blocked=1
fi

exit "$blocked"
