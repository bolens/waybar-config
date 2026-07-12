#!/usr/bin/env bash
# Generate theme/dock-appicons.generated.css from icons.appicon + dock-apps.json.
# Runtime files under theme/dock-appicons/<id> are maintained by dock-launcher/prefetch.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
manifest="$WAYBAR_HOME/data/dock-apps.json"
out="$WAYBAR_HOME/theme/dock-appicons.generated.css"

mkdir -p "$WAYBAR_HOME/theme"

enabled=false
size=18
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  enabled="$(jq -r '.icons.appicon.enabled // false' "$settings")"
  size="$(jq -r '.icons.appicon.size // 18' "$settings")"
fi

case "$enabled" in
  true | True | TRUE | 1 | yes | Yes | YES | on | On | ON) ;;
  *)
    printf '%s\n' '/* icons.appicon disabled */' >"$out"
    exit 0
    ;;
esac

if [ ! -f "$manifest" ]; then
  printf '%s\n' '/* icons.appicon enabled but dock-apps.json missing */' >"$out"
  exit 0
fi

{
  printf '%s\n' '/* Generated from icons.appicon — do not edit by hand */'
  printf '%s\n' '/* Exact NxN PNGs in theme/dock-appicons/ (GTK3 often ignores background-size). */'
  printf '#dock-apps label.appicon {\n'
  printf '    min-width: %spx;\n' "$size"
  printf '    min-height: %spx;\n' "$size"
  printf '    background-size: %spx %spx;\n' "$size" "$size"
  printf '    background-repeat: no-repeat;\n'
  printf '    background-position: center;\n'
  printf '}\n'
  jq -r 'keys[]' "$manifest" | while read -r id; do
    [ -n "$id" ] || continue
    printf '\n#custom-dock-%s.appicon {\n' "$id"
    printf '    background-image: url("dock-appicons/%s");\n' "$id"
    printf '}\n'
  done
} >"$out"

if [ -x "$WAYBAR_SCRIPTS/dock/dock-appicon-prefetch.sh" ]; then
  "$WAYBAR_SCRIPTS/dock/dock-appicon-prefetch.sh" || true
fi
