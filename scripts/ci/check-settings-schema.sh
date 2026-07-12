#!/usr/bin/env bash
# Fail on unknown top-level keys in compiled waybar-settings.json.
# Catches typos in forks / merges that would otherwise silently fall through.
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
SCRIPT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ALLOWLIST="${1:-$SCRIPT_ROOT/scripts/ci/lib/settings-top-level-allowlist.txt}"
settings="${WAYBAR_SETTINGS:-$WAYBAR_HOME/data/waybar-settings.json}"
settings_jsonc="${settings}c"

if [ ! -f "$settings" ] && [ -f "$settings_jsonc" ]; then
  if [ -f "$WAYBAR_HOME/scripts/lib/waybar-settings.sh" ]; then
    # shellcheck source=../lib/waybar-settings.sh
    . "$WAYBAR_HOME/scripts/lib/waybar-settings.sh"
  elif [ -f "$SCRIPT_ROOT/scripts/lib/waybar-settings.sh" ]; then
    # shellcheck source=../lib/waybar-settings.sh
    . "$SCRIPT_ROOT/scripts/lib/waybar-settings.sh"
  fi
fi

if [ ! -f "$settings" ]; then
  printf 'FAIL missing settings file: %s\n' "$settings" >&2
  exit 1
fi
if [ ! -f "$ALLOWLIST" ]; then
  printf 'FAIL missing allowlist: %s\n' "$ALLOWLIST" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || {
  printf 'FAIL jq required\n' >&2
  exit 1
}

mapfile -t allowed_keys < <(grep -vE '^\s*(#|$)' "$ALLOWLIST" | sort -u)
if [ "${#allowed_keys[@]}" -eq 0 ]; then
  printf 'FAIL allowlist is empty: %s\n' "$ALLOWLIST" >&2
  exit 1
fi

unknown=$(
  jq -r 'keys[]' "$settings" | sort -u | while IFS= read -r key; do
    found=0
    for a in "${allowed_keys[@]}"; do
      if [ "$a" = "$key" ]; then
        found=1
        break
      fi
    done
    [ "$found" -eq 1 ] || printf '%s\n' "$key"
  done
)

if [ -n "$unknown" ]; then
  printf 'FAIL unknown top-level settings key(s) in %s:\n' "$settings" >&2
  printf '  %s\n' "$unknown" >&2
  printf 'Update scripts/ci/lib/settings-top-level-allowlist.txt if intentional.\n' >&2
  exit 1
fi

printf 'ok settings top-level keys match allowlist (%s keys)\n' "${#allowed_keys[@]}"
