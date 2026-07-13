#!/usr/bin/env bash
# Generate dock window slot layout from dock_windows.slot_count (+ optional appicon PNGs).
# App icons are keyed by dock-apps id (appicon-<id>) so per-output bars share stable files.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/appicon-lib.sh"

settings="${WAYBAR_HOME}/data/waybar-settings.json"
manifest="${WAYBAR_HOME}/data/dock-apps.json"
out="$WAYBAR_HOME/theme/dock-windows.generated.css"
mkdir -p "$WAYBAR_HOME/theme"

# Match generate-dock-windows-modules.sh: clamp 1–16, default 12.
slot_count="$(waybar_css_slot_count "$settings" dock_windows 12 1 16)"

hit="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-hit')"
inactive="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-inactive')"
active="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-active')"
hit_hover="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-hit:hover')"
hidden="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.hidden')"
appicon_base="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.appicon')"

appicon_enabled=false
size=18
pad=8
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  case "$(jq -r '.icons.appicon.enabled // false' "$settings")" in
    true | True | TRUE | 1 | yes | Yes | YES | on | On | ON) appicon_enabled=true ;;
  esac
  size="$(jq -r '.icons.appicon.size // 18' "$settings")"
  pad="$(jq -r '.icons.appicon.pad // 8' "$settings")"
fi

{
  cat <<EOF
/* Generated from dock_windows.slot_count — do not edit by hand */

${hit} {
    background-color: transparent;
    background-image: none;
    border: none;
    box-shadow: none;
    padding: 0 12px;
    margin: 0;
    min-width: 24px;
    border-radius: 8px;
    transition:
        color 120ms cubic-bezier(0.4, 0, 0.2, 1),
        opacity 120ms cubic-bezier(0.4, 0, 0.2, 1),
        background-color 120ms cubic-bezier(0.4, 0, 0.2, 1);
}

${inactive} {
    opacity: 0.7;
}

${active} {
    opacity: 1;
}

${hit_hover} {
    opacity: 1;
}

${hidden} {
    background-color: transparent;
    margin: 0;
    padding: 0;
    min-width: 0;
}

/* Hide glyph paint whenever .appicon is set (PNG may load a tick later).
 * Keep font metrics — font-size:0 collapses the label and breaks Plasma tooltips. */
${appicon_base} {
    color: transparent;
    text-shadow: none;
}

/* Tooltips attach to the GtkLabel child — match the icon tile hitbox. */
${appicon_base} label {
    padding: ${pad}px;
    min-width: ${size}px;
    min-height: ${size}px;
}
EOF

  if [ "$appicon_enabled" = true ] && [ -f "$manifest" ] && command -v jq >/dev/null 2>&1; then
    printf '\n/* icons.appicon: per-app PNGs (shared across outputs; class appicon-<id>) */\n'
    mapfile -t app_ids < <(jq -r 'keys[]' "$manifest")
    for id in "${app_ids[@]}"; do
      [ -n "$id" ] || continue
      # Prefer launcher materializations; fall back to theme/dock-win-icons/<id>.png.
      # file:// absolute URLs survive reload_style_on_change (relative urls often don't).
      url="$(waybar_appicon_css_file_url "theme/dock-appicons/${id}.png")"
      alt_url="$(waybar_appicon_css_file_url "theme/dock-win-icons/${id}.png")"
      # Slot list for this app class
      first=1
      for ((i = 0; i < slot_count; i++)); do
        if [ "$first" -eq 1 ]; then
          printf '#custom-dock-win-%s.appicon-%s' "$i" "$id"
          first=0
        else
          printf ',\n#custom-dock-win-%s.appicon-%s' "$i" "$id"
        fi
      done
      printf ' {\n'
      printf '    background-image: url("%s");\n' "$url"
      printf '    background-color: transparent;\n'
      printf '    background-repeat: no-repeat;\n'
      printf '    background-position: center;\n'
      printf '    background-size: %spx %spx;\n' "$size" "$size"
      printf '    color: transparent;\n'
      printf '    text-shadow: none;\n'
      # No font-size:0 — preserves hover hitbox for Plasma tooltips.
      printf '    padding: %spx;\n' "$pad"
      printf '    min-width: %spx;\n' "$size"
      printf '    min-height: %spx;\n' "$size"
      printf '}\n'
      # Label hitbox (Waybar tooltips bind to GtkLabel, not the padded module box).
      first=1
      for ((i = 0; i < slot_count; i++)); do
        if [ "$first" -eq 1 ]; then
          printf '#custom-dock-win-%s.appicon-%s label' "$i" "$id"
          first=0
        else
          printf ',\n#custom-dock-win-%s.appicon-%s label' "$i" "$id"
        fi
      done
      printf ' {\n'
      printf '    padding: %spx;\n' "$pad"
      printf '    min-width: %spx;\n' "$size"
      printf '    min-height: %spx;\n' "$size"
      printf '}\n'
      # Hover / active keep the image (avoid shorthand wipe) and use fallback URL if needed.
      first=1
      for ((i = 0; i < slot_count; i++)); do
        if [ "$first" -eq 1 ]; then
          printf '#custom-dock-win-%s.appicon-%s:hover' "$i" "$id"
          first=0
        else
          printf ',\n#custom-dock-win-%s.appicon-%s:hover' "$i" "$id"
        fi
      done
      printf ' {\n'
      printf '    background-color: rgba(0, 229, 255, 0.10);\n'
      printf '    background-image: url("%s");\n' "$url"
      printf '    color: transparent;\n'
      printf '}\n'
      first=1
      for ((i = 0; i < slot_count; i++)); do
        if [ "$first" -eq 1 ]; then
          printf '#custom-dock-win-%s.appicon-%s.dock-win-active' "$i" "$id"
          first=0
        else
          printf ',\n#custom-dock-win-%s.appicon-%s.dock-win-active' "$i" "$id"
        fi
      done
      printf ' {\n'
      printf '    background-color: rgba(255, 42, 127, 0.14);\n'
      printf '    background-image: url("%s");\n' "$url"
      printf '    color: transparent;\n'
      printf '    text-shadow: none;\n'
      printf '}\n\n'
      # Silence unused alt_url for shellcheck when launcher png is the SoT.
      : "$alt_url"
    done
  fi
} >"$out"

# Stub only — unknown-app rules are appended at runtime (file:// urls).
printf '%s\n' '/* Runtime dock-windows appicon rules — do not edit by hand */' \
  >"$WAYBAR_HOME/theme/dock-win-runtime.generated.css"
