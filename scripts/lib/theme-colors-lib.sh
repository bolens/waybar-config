#!/usr/bin/env bash
# Theme color resolve helpers for generators (preset merge + hex/rgba utils).
# Expects jq; callers typically set WAYBAR_HOME and pass a settings JSON path.

# Print normalized theme.mode: static | wallpaper | preset (unknown → static).
# Usage: waybar_theme_resolve_mode [SETTINGS_JSON]
waybar_theme_resolve_mode() {
  local s="${1:-${settings:?waybar_theme_resolve_mode: settings unset}}"
  local mode
  mode="$(jq -r '.theme.mode // "static"' "$s")"
  case "$mode" in
    static | wallpaper | preset) ;;
    *) mode="static" ;;
  esac
  printf '%s' "$mode"
}

# Print compact JSON object of resolved theme colors.
# When mode=preset, merges data/themes/<preset>.{jsonc,json} colors under settings overrides.
# Usage: waybar_theme_resolve_colors [SETTINGS_JSON]
waybar_theme_resolve_colors() {
  local s="${1:-${settings:?waybar_theme_resolve_colors: settings unset}}"
  local mode colors_json preset_name cand preset_colors
  mode="$(waybar_theme_resolve_mode "$s")"
  colors_json="$(jq -c '.theme.colors // {}' "$s")"

  if [ "$mode" = "preset" ]; then
    preset_name="$(jq -r '.theme.preset // "cyberpunk"' "$s")"
    for cand in \
      "${WAYBAR_HOME}/data/themes/${preset_name}.jsonc" \
      "${WAYBAR_HOME}/data/themes/${preset_name}.json"; do
      if [ -f "$cand" ]; then
        # Strip // comments for jsonc, then merge: preset base, settings colors override.
        preset_colors="$(
          sed -E 's://.*$::g' "$cand" | jq -c '.colors // .' 2>/dev/null || true
        )"
        if [ -n "$preset_colors" ] && [ "$preset_colors" != "null" ]; then
          colors_json="$(jq -cn --argjson p "$preset_colors" --argjson o "$colors_json" '$p + $o')"
        fi
        break
      fi
    done
  fi
  printf '%s' "$colors_json"
}

# hex/rgba → "r, g, b"; empty if unparseable.
# Usage: waybar_theme_color_rgb_csv COLOR
waybar_theme_color_rgb_csv() {
  local c="$1"
  if [[ "$c" =~ ^#([0-9a-fA-F]{6})$ ]]; then
    local h="${BASH_REMATCH[1]}"
    printf '%d, %d, %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
  elif [[ "$c" =~ ^#([0-9a-fA-F]{3})$ ]]; then
    local h="${BASH_REMATCH[1]}"
    printf '%d, %d, %d' "0x${h:0:1}${h:0:1}" "0x${h:1:1}${h:1:1}" "0x${h:2:1}${h:2:1}"
  elif [[ "$c" =~ rgba?\(\ *([0-9.]+)\ *,\ *([0-9.]+)\ *,\ *([0-9.]+) ]]; then
    printf '%d, %d, %d' "${BASH_REMATCH[1]%.*}" "${BASH_REMATCH[2]%.*}" "${BASH_REMATCH[3]%.*}"
  else
    printf ''
  fi
}

# Produce rgba(r,g,b,a); if unparseable, echo the solid color (or FALLBACK if set).
# Usage: waybar_theme_color_with_alpha COLOR ALPHA [FALLBACK]
waybar_theme_color_with_alpha() {
  local c="$1" a="$2" fallback="${3:-}"
  local rgb
  rgb="$(waybar_theme_color_rgb_csv "$c")"
  if [[ -n "$rgb" ]]; then
    printf 'rgba(%s, %s)' "$rgb" "$a"
  elif [[ -n "$fallback" ]]; then
    printf '%s' "$fallback"
  else
    printf '%s' "$c"
  fi
}

# Read one key from a compact colors JSON with default.
# Usage: waybar_theme_color_get COLORS_JSON KEY DEFAULT
waybar_theme_color_get() {
  local colors_json="$1" key="$2" default="$3"
  jq -rn --argjson c "$colors_json" --arg k "$key" --arg d "$default" \
    'if ($c[$k] != null and $c[$k] != "") then $c[$k] else $d end'
}
