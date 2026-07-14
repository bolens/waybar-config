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

# signals.* offsets must be unique positive integers (Waybar RTMIN+N).
signal_report=$(
  jq -r '
    (.signals // {}) as $sig
    | ($sig | to_entries) as $entries
    | if ($entries | length) == 0 then
        "empty"
      else
        ($entries | map(select(.value | type != "number" or . < 1 or (. % 1) != 0))) as $bad
        | if ($bad | length) > 0 then
            "invalid:" + ($bad | map("\(.key)=\(.value)") | join(","))
          else
            ($entries | group_by(.value) | map(select(length > 1))
              | map("\((.[0].value|tostring)):\([.[].key] | join("+"))") | join(";")) as $dups
            | if $dups == "" then "ok:\(($entries | length))"
              else "dup:" + $dups end
          end
      end
  ' "$settings"
)
case "$signal_report" in
  empty)
    printf 'FAIL signals map missing or empty in %s\n' "$settings" >&2
    exit 1
    ;;
  invalid:*)
    printf 'FAIL signals.* values must be positive integers: %s\n' "${signal_report#invalid:}" >&2
    exit 1
    ;;
  dup:*)
    printf 'FAIL duplicate signals.* offsets (each RTMIN must be unique):\n' >&2
    printf '  %s\n' "${signal_report#dup:}" | tr ';' '\n' | sed 's/^/  /' >&2
    exit 1
    ;;
  ok:*)
    ;;
  *)
    printf 'FAIL unexpected signals report: %s\n' "$signal_report" >&2
    exit 1
    ;;
esac

printf 'ok settings top-level keys match allowlist (%s keys); signals unique (%s)\n' \
  "${#allowed_keys[@]}" "${signal_report#ok:}"
