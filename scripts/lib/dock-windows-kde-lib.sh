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

# Drop empty / unexpanded "$WAYBAR_OUTPUT_NAME" from click argv.
dock_windows_normalize_output_arg() {
  local name="${1:-}"
  case "$name" in
    '' | '$WAYBAR_OUTPUT_NAME' | '${WAYBAR_OUTPUT_NAME}')
      printf ''
      ;;
    *)
      printf '%s' "$name"
      ;;
  esac
}

# Resolve which output a dock action belongs to.
# Waybar sets WAYBAR_OUTPUT_NAME for exec, but not for on-click (Alexays/Waybar#3848),
# so clicks must fall back to the compositor's pointer/active output.
dock_windows_resolve_output() {
  local explicit="${1:-}" name=""
  explicit="$(dock_windows_normalize_output_arg "$explicit")"
  if [ -n "$explicit" ]; then
    printf '%s' "$explicit"
    return 0
  fi
  name="$(dock_windows_normalize_output_arg "${WAYBAR_OUTPUT_NAME:-}")"
  if [ -n "$name" ]; then
    printf '%s' "$name"
    return 0
  fi
  dock_windows_per_output_enabled || {
    printf ''
    return 0
  }
  if command -v qdbus6 >/dev/null 2>&1; then
    name=$(timeout 1 qdbus6 org.kde.KWin /KWin org.kde.KWin.activeOutputName 2>/dev/null || true)
    name=$(printf '%s' "$name" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    if [ -n "$name" ]; then
      printf '%s' "$name"
      return 0
    fi
  fi
  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    name=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' | head -1 || true)
    if [ -n "$name" ] && [ "$name" != "null" ]; then
      printf '%s' "$name"
      return 0
    fi
  fi
  printf ''
}

# Runtime bind files: slot-status (exec, has OUTPUT_NAME) → click (often missing it).
dock_windows_slot_bind_dir() {
  local out safe
  out="$(dock_windows_normalize_output_arg "${1:-}")"
  if [ -z "$out" ]; then
    printf '%s' "${XDG_RUNTIME_DIR:-/tmp}/waybar-dock/slots/_all"
    return 0
  fi
  safe=$(printf '%s' "$out" | sed 's/[^A-Za-z0-9_-]/_/g')
  printf '%s' "${XDG_RUNTIME_DIR:-/tmp}/waybar-dock/slots/${safe}"
}

dock_windows_bind_slot() {
  local slot="${1:-}" id="${2:-}" title="${3:-}" app="${4:-}" out="${5:-${WAYBAR_OUTPUT_NAME:-}}"
  local dir path
  [ -n "$slot" ] || return 0
  [[ "$slot" =~ ^[0-9]+$ ]] || return 0
  dir="$(dock_windows_slot_bind_dir "$out")"
  mkdir -p "$dir"
  path="$dir/$slot.json"
  jq -cn \
    --arg id "$id" \
    --arg title "$title" \
    --arg app "$app" \
    --arg out "$(dock_windows_normalize_output_arg "$out")" \
    '{id:$id, title:$title, app:$app, output:$out}' >"$path.tmp.$$" 2>/dev/null \
    && mv -f "$path.tmp.$$" "$path" || rm -f "$path.tmp.$$"
}

dock_windows_read_slot_bind() {
  local slot="${1:-}" out="${2:-${WAYBAR_OUTPUT_NAME:-}}" dir path
  [ -n "$slot" ] || return 1
  dir="$(dock_windows_slot_bind_dir "$out")"
  path="$dir/$slot.json"
  [ -f "$path" ] || return 1
  cat "$path"
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

# Populate DOCK_WINDOWS_ICON_MAP (glyph), APPICON_QUERY, and APP_ID (dock-apps key).
# shellcheck disable=SC2034
dock_windows_load_icon_map() {
  declare -gA DOCK_WINDOWS_ICON_MAP=()
  declare -gA DOCK_WINDOWS_APPICON_QUERY=()
  declare -gA DOCK_WINDOWS_APP_ID=()
  local manifest="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/dock-apps.json"
  [ -f "$manifest" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local cls icon query app_id
  while IFS=$'\t' read -r cls icon query app_id; do
    [ -n "$cls" ] || continue
    [ -n "$icon" ] && DOCK_WINDOWS_ICON_MAP["$cls"]="$icon"
    [ -n "$query" ] && DOCK_WINDOWS_APPICON_QUERY["$cls"]="$query"
    [ -n "$app_id" ] && DOCK_WINDOWS_APP_ID["$cls"]="$app_id"
  done < <(
    jq -r '
      to_entries[]
      | . as $e
      | ($e.value.icon // empty) as $icon
      | (
          $e.value.appicon
          // $e.value.launch
          // ($e.value.process_names[0] // empty)
          // ($e.value.wm_classes[0] // empty)
          // $e.key
        ) as $query
      | select($icon != "" or $query != "")
      | (($e.value.wm_classes // []) + [$e.key])
      | .[]
      | select(. != null and . != "")
      | "\(.|ascii_downcase)\t\($icon)\t\($query)\t\($e.key)"
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
    *steam_app_*)
      printf '󰊖'
      return 0
      ;;
    *steam*)
      printf '󰓓'
      return 0
      ;;
    *heroic*)
      printf '󰊖'
      return 0
      ;;
    *lutris*)
      printf '󰙆'
      return 0
      ;;
    *obsidian*)
      printf '󱞁'
      return 0
      ;;
    *krita*)
      printf '󰝼'
      return 0
      ;;
    *dolphin* | *thunar* | *nautilus* | *files*)
      printf '󰉋'
      return 0
      ;;
    *code* | *cursor* | *codium*)
      printf '󰨞'
      return 0
      ;;
    *firefox* | *zen* | *floorp* | *chrome* | *chromium* | *brave* | *helium* | *youtube* | *http*)
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

# Stable CSS class key for dock-windows icons (shared across outputs — no slot race).
# Prefer dock-apps ids; keep steam_app_* / unknown classes distinct so games ≠ Steam.
dock_windows_appicon_key_for() {
  local title="${1:-}"
  local app="${2:-}"
  local key title_lower cls bare
  key=$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')
  title_lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')
  bare="${key%.desktop}"
  bare="${bare##*.}"

  # Steam games must not collapse onto the Steam client icon.
  if [[ "$key" == steam_app_* ]]; then
    printf 'steam-app-%s' "${key#steam_app_}"
    return 0
  fi
  if [[ "$bare" == steam_app_* ]]; then
    printf 'steam-app-%s' "${bare#steam_app_}"
    return 0
  fi

  if [ -n "$key" ] && [ -n "${DOCK_WINDOWS_APP_ID[$key]:-}" ]; then
    printf '%s' "${DOCK_WINDOWS_APP_ID[$key]}"
    return 0
  fi
  if [ -n "$bare" ] && [ -n "${DOCK_WINDOWS_APP_ID[$bare]:-}" ]; then
    printf '%s' "${DOCK_WINDOWS_APP_ID[$bare]}"
    return 0
  fi

  # Title heuristics only (never substring-match app ids like steam_app_* → steam).
  for cls in "${!DOCK_WINDOWS_APP_ID[@]}"; do
    if [ "${#cls}" -gt 3 ] && [[ "$title_lower" == *"$cls"* ]]; then
      printf '%s' "${DOCK_WINDOWS_APP_ID[$cls]}"
      return 0
    fi
  done

  case "$title_lower" in
    *discord* | *vesktop* | *webcord*)
      printf 'discord'
      return 0
      ;;
    *heroic*)
      printf 'heroic'
      return 0
      ;;
    *lutris*)
      printf 'lutris'
      return 0
      ;;
    *obsidian*)
      printf 'obsidian'
      return 0
      ;;
    *krita*)
      printf 'krita'
      return 0
      ;;
    *dolphin* | *thunar* | *nautilus*)
      printf 'files'
      return 0
      ;;
    *cursor*)
      printf 'cursor'
      return 0
      ;;
    *code-insiders* | *code*insiders*)
      printf 'vscode'
      return 0
      ;;
    *helium*)
      printf 'helium'
      return 0
      ;;
    *floorp*)
      printf 'floorp'
      return 0
      ;;
    *zen* | *firefox*)
      printf 'browser'
      return 0
      ;;
    *ghostty* | *kitty* | *konsole* | *foot*)
      printf 'terminal'
      return 0
      ;;
    *zed*)
      printf 'zed'
      return 0
      ;;
  esac

  # Exact Steam client title/class only (not steam_app_*).
  case "$key" in
    steam | steamwebhelper)
      printf 'steam'
      return 0
      ;;
  esac
  case "$title_lower" in
    steam | steam\ -\ *)
      printf 'steam'
      return 0
      ;;
  esac

  # Unknown app class → sanitized key for runtime CSS (if resolvable).
  if [ -n "$bare" ] && [[ "$bare" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf '%s' "$bare"
    return 0
  fi
  return 1
}

# appicon resolve query for a window (dock-apps map + title heuristics). Empty = no PNG.
dock_windows_appicon_query_for() {
  local title="${1:-}"
  local app="${2:-}"
  local key title_lower cls bare app_key
  key=$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')
  title_lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')
  bare="${key%.desktop}"
  bare="${bare##*.}"

  # Prefer the raw Steam app id so appicon can resolve steam_icon_<id>.
  if [[ "$key" == steam_app_* ]]; then
    printf '%s' "$key"
    return 0
  fi
  if [[ "$bare" == steam_app_* ]]; then
    printf '%s' "$bare"
    return 0
  fi

  if [ -n "$key" ] && [ -n "${DOCK_WINDOWS_APPICON_QUERY[$key]:-}" ]; then
    printf '%s' "${DOCK_WINDOWS_APPICON_QUERY[$key]}"
    return 0
  fi
  if [ -n "$bare" ] && [ -n "${DOCK_WINDOWS_APPICON_QUERY[$bare]:-}" ]; then
    printf '%s' "${DOCK_WINDOWS_APPICON_QUERY[$bare]}"
    return 0
  fi

  # Title-only fuzzy map (avoid app-id substring collisions).
  for cls in "${!DOCK_WINDOWS_APPICON_QUERY[@]}"; do
    if [ "${#cls}" -gt 3 ] && [[ "$title_lower" == *"$cls"* ]]; then
      printf '%s' "${DOCK_WINDOWS_APPICON_QUERY[$cls]}"
      return 0
    fi
  done

  app_key="$(dock_windows_appicon_key_for "$title" "$app" || true)"
  if [ -n "$app_key" ] && [ -n "${DOCK_WINDOWS_APPICON_QUERY[$app_key]:-}" ]; then
    printf '%s' "${DOCK_WINDOWS_APPICON_QUERY[$app_key]}"
    return 0
  fi
  if [ -n "$key" ]; then
    printf '%s' "$key"
    return 0
  fi
  return 1
}

# Ensure theme/dock-win-runtime.generated.css has a rule for appicon-<key>.
# Waybar reload_style_on_change picks this up for Steam games / unknown apps.
dock_windows_ensure_runtime_css() {
  local app_key="$1"
  local url="$2"
  local size="${3:-18}"
  local pad="${4:-8}"
  local slot_count css runtime tmp i first lock
  local settings="${WAYBAR_HOME}/data/waybar-settings.json"

  [ -n "$app_key" ] && [ -n "$url" ] || return 1
  [[ "$app_key" =~ ^[A-Za-z0-9_-]+$ ]] || return 1

  runtime="$WAYBAR_HOME/theme/dock-win-runtime.generated.css"
  mkdir -p "$WAYBAR_HOME/theme"
  if [ -f "$runtime" ] && grep -Fq "appicon-${app_key}" "$runtime" 2>/dev/null; then
    return 0
  fi

  lock="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-runtime-css.lock"
  (
    flock 8 || exit 0
    if [ -f "$runtime" ] && grep -Fq "appicon-${app_key}" "$runtime" 2>/dev/null; then
      exit 0
    fi

    slot_count=12
    if [ -f "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh" ]; then
      # shellcheck source=css-selectors-lib.sh
      . "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh"
      slot_count="$(waybar_css_slot_count "$settings" dock_windows 12 1 16)"
    fi

    {
      if [ -f "$runtime" ]; then
        cat "$runtime"
      else
        printf '%s\n' '/* Runtime dock-windows appicon rules — do not edit by hand */'
      fi
      first=1
      for ((i = 0; i < slot_count; i++)); do
        if [ "$first" -eq 1 ]; then
          printf '#custom-dock-win-%s.appicon-%s' "$i" "$app_key"
          first=0
        else
          printf ',\n#custom-dock-win-%s.appicon-%s' "$i" "$app_key"
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
      first=1
      for ((i = 0; i < slot_count; i++)); do
        if [ "$first" -eq 1 ]; then
          printf '#custom-dock-win-%s.appicon-%s label' "$i" "$app_key"
          first=0
        else
          printf ',\n#custom-dock-win-%s.appicon-%s label' "$i" "$app_key"
        fi
      done
      printf ' {\n'
      printf '    padding: %spx;\n' "$pad"
      printf '    min-width: %spx;\n' "$size"
      printf '    min-height: %spx;\n' "$size"
      printf '}\n'
    } >"${runtime}.tmp.$$"
    # Skip mv when unchanged — each rewrite triggers reload_style_on_change flicker.
    if [ -f "$runtime" ] && cmp -s "${runtime}.tmp.$$" "$runtime"; then
      rm -f "${runtime}.tmp.$$"
    else
      mv -f "${runtime}.tmp.$$" "$runtime"
    fi
  ) 8>"$lock"
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
