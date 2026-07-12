#!/usr/bin/env bash
# Generate theme/dock-appicons.generated.css from icons.appicon + dock-apps.json.
# Runtime PNGs under theme/dock-appicons/<id>.png from dock-launcher/prefetch.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
manifest="$WAYBAR_HOME/data/dock-apps.json"
out="$WAYBAR_HOME/theme/dock-appicons.generated.css"
icon_dir="$WAYBAR_HOME/theme/dock-appicons"

mkdir -p "$WAYBAR_HOME/theme"

enabled=false
size=18
gap=10
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  enabled="$(jq -r '.icons.appicon.enabled // false' "$settings")"
  size="$(jq -r '.icons.appicon.size // 18' "$settings")"
  gap="$(jq -r '.icons.appicon.gap // 10' "$settings")"
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

# Prefetch first so file:// URLs point at real PNGs.
if [ "${1:-}" != "--no-prefetch" ] && [ -x "$WAYBAR_SCRIPTS/dock/dock-appicon-prefetch.sh" ]; then
  "$WAYBAR_SCRIPTS/dock/dock-appicon-prefetch.sh" || true
fi

css_url_for() {
  local id="$1"
  local png="$icon_dir/${id}.png"
  printf 'file://%s' "$png"
}

{
  printf '%s\n' '/* Generated from icons.appicon — do not edit by hand */'
  printf '%s\n' '/* After semantic-colors: use background-color on pills so icons survive hover. */'
  printf '%s\n' '/* margin-right = gap between bordered boxes; padding = space around PNG. */'
  printf '#dock-apps .drawer-child.appicon,\n'
  printf '#dock-apps label.appicon {\n'
  printf '    font-size: 0;\n'
  printf '    color: transparent;\n'
  printf '    text-shadow: none;\n'
  printf '    min-width: %spx;\n' "$size"
  printf '    min-height: %spx;\n' "$size"
  printf '    padding: 0 2px;\n'
  printf '    margin-top: 4px;\n'
  printf '    margin-bottom: 4px;\n'
  printf '    margin-left: 0;\n'
  printf '    margin-right: %spx;\n' "$gap"
  printf '    background-repeat: no-repeat;\n'
  printf '    background-position: center;\n'
  printf '    background-size: %spx %spx;\n' "$size" "$size"
  printf '}\n'
  jq -r 'keys[]' "$manifest" | while read -r id; do
    [ -n "$id" ] || continue
    url="$(css_url_for "$id")"
    printf '\n#custom-dock-%s.appicon,\n' "$id"
    printf '#custom-dock-%s.appicon:hover,\n' "$id"
    printf '#custom-dock-%s.appicon:active,\n' "$id"
    printf '#custom-dock-%s.appicon.ready,\n' "$id"
    printf '#custom-dock-%s.appicon.running {\n' "$id"
    printf '    background-image: url("%s");\n' "$url"
    printf '    background-color: transparent;\n'
    printf '    color: transparent;\n'
    printf '    text-shadow: none;\n'
    printf '    font-size: 0;\n'
    printf '    padding: 0 2px;\n'
    printf '    margin-right: %spx;\n' "$gap"
    printf '    min-width: %spx;\n' "$size"
    printf '    min-height: %spx;\n' "$size"
    printf '    background-repeat: no-repeat;\n'
    printf '    background-position: center;\n'
    printf '    background-size: %spx %spx;\n' "$size" "$size"
    printf '}\n'
    printf '#custom-dock-%s.appicon:hover {\n' "$id"
    printf '    background-color: rgba(0, 229, 255, 0.10);\n'
    printf '    background-image: url("%s");\n' "$url"
    printf '}\n'
    printf '#custom-dock-%s.appicon.running {\n' "$id"
    printf '    box-shadow: 0 0 6px rgba(0, 229, 255, 0.7);\n'
    printf '}\n'
  done
} >"$out"
