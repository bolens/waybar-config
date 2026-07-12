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
gap=12
pad=8
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  enabled="$(jq -r '.icons.appicon.enabled // false' "$settings")"
  size="$(jq -r '.icons.appicon.size // 18' "$settings")"
  gap="$(jq -r '.icons.appicon.gap // 12' "$settings")"
  pad="$(jq -r '.icons.appicon.pad // 8' "$settings")"
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

if [ "${1:-}" != "--no-prefetch" ] && [ -x "$WAYBAR_SCRIPTS/dock/dock-appicon-prefetch.sh" ]; then
  "$WAYBAR_SCRIPTS/dock/dock-appicon-prefetch.sh" || true
fi

css_url_for() {
  local id="$1"
  printf 'file://%s/%s.png' "$icon_dir" "$id"
}

mapfile -t app_ids < <(jq -r 'keys[]' "$manifest")

{
  printf '%s\n' '/* Generated from icons.appicon — do not edit by hand */'
  printf '%s\n' '/* Layout applies to every dock launcher id (even glyph fallback) for even gaps. */'
  printf '%s\n' '/* .appicon adds the PNG; gap/pad from icons.appicon.gap / .pad */'

  # Shared layout for all launcher modules — do not require .appicon.
  first=1
  for id in "${app_ids[@]}"; do
    [ -n "$id" ] || continue
    if [ "$first" -eq 1 ]; then
      printf '#custom-dock-%s' "$id"
      first=0
    else
      printf ',\n#custom-dock-%s' "$id"
    fi
  done
  printf ' {\n'
  # Equal padding so running/hover box-shadow is not clipped at the widget edge (GTK).
  printf '    padding: %spx;\n' "$pad"
  printf '    margin-top: 4px;\n'
  printf '    margin-bottom: 4px;\n'
  printf '    margin-left: 0;\n'
  printf '    margin-right: %spx;\n' "$gap"
  printf '    min-width: %spx;\n' "$size"
  printf '    min-height: %spx;\n' "$size"
  printf '    border-right: 1px solid rgba(0, 229, 255, 0.12);\n'
  printf '    border-radius: 6px;\n'
  printf '}\n'

  # Last launcher in the drawer still needs a right margin for visual rhythm, or
  # zero it — keep gap on all so neighbors never glue when order changes.
  printf '\n'

  for id in "${app_ids[@]}"; do
    [ -n "$id" ] || continue
    url="$(css_url_for "$id")"
    printf '#custom-dock-%s.appicon,\n' "$id"
    printf '#custom-dock-%s.appicon:hover,\n' "$id"
    printf '#custom-dock-%s.appicon:active,\n' "$id"
    printf '#custom-dock-%s.appicon.ready,\n' "$id"
    printf '#custom-dock-%s.appicon.running {\n' "$id"
    printf '    background-image: url("%s");\n' "$url"
    printf '    background-color: transparent;\n'
    printf '    background-repeat: no-repeat;\n'
    printf '    background-position: center;\n'
    printf '    background-size: %spx %spx;\n' "$size" "$size"
    printf '    color: transparent;\n'
    printf '    text-shadow: none;\n'
    printf '    font-size: 0;\n'
    printf '    padding: %spx;\n' "$pad"
    printf '    margin-right: %spx;\n' "$gap"
    printf '}\n'
    printf '#custom-dock-%s.appicon:hover {\n' "$id"
    printf '    background-color: rgba(0, 229, 255, 0.10);\n'
    printf '    background-image: url("%s");\n' "$url"
    printf '}\n'
    printf '#custom-dock-%s.appicon.running {\n' "$id"
    # Keep blur ≤ pad so GTK does not clip the glow at the widget edge.
    printf '    box-shadow: 0 0 %spx rgba(0, 229, 255, 0.7);\n' "$pad"
    printf '}\n\n'
  done
} >"$out"
