#!/usr/bin/env bash
# KDE WindowsRunner helpers for dock-windows (parse + per_output).
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

_dock_windows_kde_py() {
  printf '%s' "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.py"
}

# Return 0 if qdbus6 is available (respects WAYBAR_TEST_NO_QDBUS=1 for CI).
dock_windows_kde_has_qdbus() {
  case "${WAYBAR_TEST_NO_QDBUS:-}" in
    1 | true | TRUE | yes | YES) return 1 ;;
  esac
  command -v qdbus6 >/dev/null 2>&1
}

# Return 0 if dock_windows.per_output is true/absent (default true).
dock_windows_per_output_enabled() {
  local _val="true"
  if type waybar_settings_get >/dev/null 2>&1; then
    _val=$(waybar_settings_get '.dock_windows.per_output' 'true')
  elif [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
    # shellcheck disable=SC1091
    . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
    _val=$(waybar_settings_get '.dock_windows.per_output' 'true')
  fi
  case "$_val" in
    false | False | FALSE | 0 | no | No | NO | null | off | Off | OFF) return 1 ;;
    *) return 0 ;;
  esac
}

# Sanitize output name for cache file suffixes.
dock_windows_cache_suffix() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    printf ''
    return 0
  fi
  printf '.%s' "$(printf '%s' "$name" | sed 's/[^A-Za-z0-9_-]/_/g')"
}

# Return 0 when dock should show app icons (default) instead of titles.
dock_windows_icons_enabled() {
  local _val="icons"
  if type waybar_settings_get >/dev/null 2>&1; then
    _val=$(waybar_settings_get '.dock_windows.display' 'icons')
  fi
  case "$_val" in
    titles | title | text | Titles | TITLE) return 1 ;;
    *) return 0 ;;
  esac
}

# Populate DOCK_WINDOWS_ICON_MAP (assoc) from data/dock-apps.json wm_classes → icon.
# shellcheck disable=SC2034
dock_windows_load_icon_map() {
  declare -gA DOCK_WINDOWS_ICON_MAP=()
  local manifest="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/dock-apps.json"
  [ -f "$manifest" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local line cls icon
  while IFS=$'\t' read -r cls icon; do
    [ -n "$cls" ] && [ -n "$icon" ] || continue
    DOCK_WINDOWS_ICON_MAP["$cls"]="$icon"
  done < <(
    jq -r '
      to_entries[]
      | . as $e
      | ($e.value.icon // empty) as $icon
      | select($icon != "")
      | (($e.value.wm_classes // []) + [$e.key])
      | .[]
      | select(. != null and . != "")
      | "\(.|ascii_downcase)\t\($icon)"
    ' "$manifest" 2>/dev/null || true
  )
}

# Resolve a nerd/font icon for an app class + title (dock strip).
dock_windows_icon_for() {
  local title="${1:-}"
  local app="${2:-}"
  local key title_lower
  key=$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')
  title_lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')

  if [ -n "$key" ] && [ -n "${DOCK_WINDOWS_ICON_MAP[$key]:-}" ]; then
    printf '%s' "${DOCK_WINDOWS_ICON_MAP[$key]}"
    return 0
  fi
  # Strip .desktop / reverse-DNS suffixes for a second lookup.
  key="${key%.desktop}"
  key="${key##*.}"
  if [ -n "$key" ] && [ -n "${DOCK_WINDOWS_ICON_MAP[$key]:-}" ]; then
    printf '%s' "${DOCK_WINDOWS_ICON_MAP[$key]}"
    return 0
  fi

  for cls in "${!DOCK_WINDOWS_ICON_MAP[@]}"; do
    if [ "${#cls}" -gt 2 ] && { [[ "$title_lower" == *"$cls"* ]] || [[ "$key" == *"$cls"* ]]; }; then
      printf '%s' "${DOCK_WINDOWS_ICON_MAP[$cls]}"
      return 0
    fi
  done

  # Common title/class heuristics when WindowsRunner omits app id.
  case "$title_lower $key" in
    *discord* | *vesktop* | *webcord*)
      printf '󰙯'
      return 0
      ;;
    *spotify*)
      printf '󰓇'
      return 0
      ;;
    *steam*)
      printf '󰓓'
      return 0
      ;;
    *code* | *cursor* | *codium*)
      printf '󰨞'
      return 0
      ;;
    *firefox* | *zen* | *floorp* | *chrome* | *chromium* | *brave* | *youtube* | *http*)
      printf '󰈹'
      return 0
      ;;
    *konsole* | *kitty* | *alacritty* | *ghostty* | *terminal* | *wezterm*)
      printf '󰆍'
      return 0
      ;;
  esac
  printf ''
}

# Parse WindowsRunner --literal stdin → title|app (status) or id|title (click).
# Usage: dock_windows_kde_parse_matches [--output NAME] [--mode status|click]
dock_windows_kde_parse_matches() {
  local py
  py="$(_dock_windows_kde_py)"
  if [ ! -f "$py" ] || ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  python3 "$py" parse "$@"
}

# Fetch + parse KWin window list. Prints lines for status/click mode.
# Usage: dock_windows_kde_list [--output NAME] [--mode status|click]
dock_windows_kde_list() {
  local out="" mode="status" raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --output)
        out="${2:-}"
        shift 2
        ;;
      --mode)
        mode="${2:-status}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if ! dock_windows_kde_has_qdbus; then
    return 2
  fi

  raw="$(timeout 2 qdbus6 --literal org.kde.KWin /WindowsRunner org.kde.krunner1.Match windows 2>/dev/null || true)"
  if [ -z "$raw" ]; then
    return 0
  fi

  if [ -n "$out" ] && dock_windows_per_output_enabled; then
    printf '%s\n' "$raw" | dock_windows_kde_parse_matches --output "$out" --mode "$mode"
  else
    printf '%s\n' "$raw" | dock_windows_kde_parse_matches --mode "$mode"
  fi
}
