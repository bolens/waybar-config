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

# console_pass must not appear with a real value in tracked settings (any indent / inline object)
if git diff --cached -U0 -- data/waybar-settings.jsonc data/waybar-settings.json 2>/dev/null \
    | grep -E '^\+.*"console_pass"[[:space:]]*:[[:space:]]*"[^"]+"' >/dev/null 2>&1; then
  echo "pre-commit: refusing console_pass in waybar-settings — use data/waybar-secrets.jsonc" >&2
  blocked=1
fi

exit "$blocked"
