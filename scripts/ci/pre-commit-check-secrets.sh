#!/usr/bin/env sh
# Block committing local secrets or credential values in tracked settings.
set -eu

blocked=0
staged=$(git diff --cached --name-only --diff-filter=ACM)

case "$staged" in
  *waybar-secrets.json*|*waybar-secrets.jsonc*)
    # Allow only the committed example template
    printf '%s\n' "$staged" | grep -v 'waybar-secrets.example.jsonc' | grep -E 'waybar-secrets\.jsonc?$' >/dev/null 2>&1 && {
      echo "pre-commit: refusing to commit data/waybar-secrets.json(c) — keep secrets local" >&2
      blocked=1
    }
    ;;
esac

# console_pass must not appear with a real value in tracked settings
if git diff --cached -U0 -- data/waybar-settings.jsonc data/waybar-settings.json 2>/dev/null \
  | grep -E '^\+[[:space:]]*"console_pass"[[:space:]]*:[[:space:]]*"[^"]+"' >/dev/null 2>&1; then
  echo "pre-commit: refusing to commit console_pass in waybar-settings — use data/waybar-secrets.jsonc" >&2
  blocked=1
fi

exit "$blocked"
