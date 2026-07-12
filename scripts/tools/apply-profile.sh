#!/usr/bin/env bash
# Deep-merge a profile JSONC into data/waybar-settings.jsonc, then optionally generate.
# Usage: apply-profile.sh [profile-name|path]
#   profile-name → data/profiles/<name>.jsonc (default: minimal-groups)
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

profile_arg="${1:-minimal-groups}"
case "$profile_arg" in
  *.jsonc | *.json | /* | ./* | ../*)
    profile_file="$profile_arg"
    ;;
  *)
    profile_file="$WAYBAR_HOME/data/profiles/${profile_arg}.jsonc"
    if [ ! -f "$profile_file" ] && [ -f "$WAYBAR_HOME/data/profiles/${profile_arg}.json" ]; then
      profile_file="$WAYBAR_HOME/data/profiles/${profile_arg}.json"
    fi
    ;;
esac

settings_jsonc="$WAYBAR_HOME/data/waybar-settings.jsonc"
settings_json="$WAYBAR_HOME/data/waybar-settings.json"

if [ ! -f "$profile_file" ]; then
  printf 'FAIL profile not found: %s\n' "$profile_file" >&2
  exit 1
fi
if [ ! -f "$settings_jsonc" ] && [ ! -f "$settings_json" ]; then
  printf 'FAIL no waybar-settings.jsonc/json under %s/data\n' "$WAYBAR_HOME" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || {
  printf 'FAIL jq required\n' >&2
  exit 1
}

# shellcheck source=../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

strip_jsonc_comments "$settings_jsonc" >"$settings_json" 2>/dev/null || true
[ -f "$settings_json" ] || {
  printf 'FAIL could not compile settings\n' >&2
  exit 1
}

profile_json=$(strip_jsonc_comments "$profile_file")
if ! printf '%s' "$profile_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  printf 'FAIL profile is not a JSON object: %s\n' "$profile_file" >&2
  exit 1
fi

# Deep merge: profile wins on conflicts; objects recurse, arrays replace.
merged=$(
  jq -n --slurpfile base "$settings_json" --argjson overlay "$profile_json" '
    def deepmerge($a; $b):
      if ($a|type) == "object" and ($b|type) == "object" then
        reduce ($a + $b | keys_unsorted[]) as $k
          ({}; .[$k] = (
            if ($a|has($k)) and ($b|has($k)) then deepmerge($a[$k]; $b[$k])
            elif ($b|has($k)) then $b[$k]
            else $a[$k] end
          ))
      else $b end;
    deepmerge($base[0]; $overlay)
  '
)

tmp="${settings_jsonc}.tmp.$$"
{
  printf '%s\n' '// Merged profile applied by scripts/tools/apply-profile.sh — review diffs before committing.'
  printf '%s\n' "$merged" | jq .
} >"$tmp"
mv -f "$tmp" "$settings_jsonc"
printf '%s\n' "$merged" >"$settings_json"

printf 'Applied profile %s → %s\n' "$profile_file" "$settings_jsonc"
if [ "${WAYBAR_APPLY_PROFILE_GENERATE:-1}" = "1" ]; then
  make -C "$WAYBAR_HOME" generate
  printf 'Ran make generate. Restart Waybar to load changes.\n'
fi
