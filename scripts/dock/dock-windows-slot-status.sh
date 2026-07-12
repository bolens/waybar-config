#!/usr/bin/env bash
# One dock-windows slot: glyph/PNG + active/inactive/hidden (workspace-switcher pattern).
# PNGs are keyed by app id (not slot) so dual-monitor bars do not clobber each other.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

slot="${1:-}"
output_arg="${2:-}"

# shellcheck source=../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=../lib/dock-windows-kde-lib.sh
. "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.sh"

WAYBAR_OUTPUT_NAME="$(dock_windows_resolve_output "$output_arg")"
export WAYBAR_OUTPUT_NAME

if [ -z "$slot" ] || ! [[ "$slot" =~ ^[0-9]+$ ]]; then
  printf '{"text":"","tooltip":"","class":["hidden"]}\n'
  exit 0
fi

list="$("$WAYBAR_SCRIPTS/dock/dock-windows-query.sh" "${WAYBAR_OUTPUT_NAME:-}" 2>/dev/null || echo '[]')"
row=$(printf '%s' "$list" | jq -c --argjson i "$slot" '.[$i] // empty' 2>/dev/null || true)

if [ -z "$row" ] || [ "$row" = "null" ]; then
  printf '{"text":"","tooltip":"","class":["hidden"]}\n'
  exit 0
fi

icon=$(printf '%s' "$row" | jq -r '.icon // ""')
title=$(printf '%s' "$row" | jq -r '.title // .app // "Window"')
app=$(printf '%s' "$row" | jq -r '.app // empty')
id=$(printf '%s' "$row" | jq -r '.id // empty')
# Bind visible slot → window id so on-click (no WAYBAR_OUTPUT_NAME) focuses the same window.
dock_windows_bind_slot "$slot" "$id" "$title" "$app" "${WAYBAR_OUTPUT_NAME:-}"

# Live focus from active-window title cache (not baked list.focused) so
# --focus-only signals update the highlighter without a KWin Match rebuild.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
active_title=""
if [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
  _safe=$(printf '%s' "$WAYBAR_OUTPUT_NAME" | sed 's/[^A-Za-z0-9_-]/_/g')
  if [ -s "$cache_dir/active-window-title-${_safe}.raw" ]; then
    active_title=$(cat "$cache_dir/active-window-title-${_safe}.raw" 2>/dev/null || true)
  fi
fi
if [ -z "$active_title" ] && [ -s "$cache_dir/active-window-title.raw" ]; then
  active_title=$(cat "$cache_dir/active-window-title.raw" 2>/dev/null || true)
fi
active_title=$(printf '%s' "$active_title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
tn=$(printf '%s' "$title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
focused=false
if [ -n "$tn" ] && [ -n "$active_title" ]; then
  if [ "$tn" = "$active_title" ] || [[ "$tn" == *"$active_title"* ]] || [[ "$active_title" == *"$tn"* ]]; then
    focused=true
  fi
fi

classes_extra=()
# Prefer existing PNGs / known dock-apps keys so focus signals never drop .appicon-*
# (glyph flash). Cold fill uses appicon --offline (prefetch warms ~/.cache/appicon).
dock_windows_appicon_prepare() {
  local query path link_dir link_path display_size theme app_key launcher_png win_png pad url id
  local known=0 dest_dir
  if [ ! -f "$WAYBAR_SCRIPTS/lib/appicon-lib.sh" ]; then
    return 0
  fi
  # shellcheck source=../lib/appicon-lib.sh
  . "$WAYBAR_SCRIPTS/lib/appicon-lib.sh"
  waybar_appicon_enabled || return 0

  dock_windows_load_icon_map || true
  app_key="$(dock_windows_appicon_key_for "$title" "$app" || true)"
  [ -n "$app_key" ] || return 0
  if ! [[ "$app_key" =~ ^[A-Za-z0-9_-]+$ ]]; then
    return 0
  fi

  display_size="$(waybar_settings_get '.icons.appicon.size' '18')"
  pad="$(waybar_settings_get '.icons.appicon.pad' '8')"
  theme="$(waybar_settings_get '.icons.appicon.theme' 'dark')"

  launcher_png="$WAYBAR_HOME/theme/dock-appicons/${app_key}.png"
  win_png="$WAYBAR_HOME/theme/dock-win-icons/${app_key}.png"
  if [ -f "$launcher_png" ] || [ -f "$win_png" ]; then
    waybar_appicon_miss_clear "$app_key" || true
    classes_extra+=(appicon "appicon-${app_key}")
    return 0
  fi

  # Generated CSS already targets appicon-<dock-apps-id>; emit class even before PNG exists
  # so font-size:0 hides the glyph instead of flashing it.
  for id in "${DOCK_WINDOWS_APP_ID[@]+"${DOCK_WINDOWS_APP_ID[@]}"}"; do
    if [ "$id" = "$app_key" ]; then
      known=1
      break
    fi
  done
  if [ "$known" = 1 ]; then
    classes_extra+=(appicon "appicon-${app_key}")
    dest_dir="$WAYBAR_HOME/theme/dock-appicons"
  else
    dest_dir="$WAYBAR_HOME/theme/dock-win-icons"
  fi

  # Recent miss stamp → do not respawn appicon on every focus signal.
  if waybar_appicon_miss_fresh "$app_key"; then
    return 0
  fi

  # No warm PNG yet and binary missing → glyph only (bin-miss stamp skips PATH thrash).
  waybar_appicon_bin >/dev/null 2>&1 || return 0

  query="$(dock_windows_appicon_query_for "$title" "$app" || true)"
  [ -n "$query" ] || query="$app_key"
  path="$(waybar_appicon_resolve "$query" "$display_size" "$theme" offline || true)"
  if [ -z "${path:-}" ] || [ ! -f "$path" ]; then
    waybar_appicon_miss_mark "$app_key" || true
    return 0
  fi

  link_path="$dest_dir/${app_key}"
  mkdir -p "$dest_dir"
  # Serialize materialize + runtime CSS across parallel slot refreshes.
  (
    flock 9 || exit 0
    if waybar_appicon_materialize "$path" "$link_path" "$display_size"; then
      waybar_appicon_miss_clear "$app_key" || true
      if [ "$known" != 1 ]; then
        url="dock-win-icons/${app_key}.png"
        dock_windows_ensure_runtime_css "$app_key" "$url" "$display_size" "$pad" || true
      fi
    else
      waybar_appicon_miss_mark "$app_key" || true
    fi
  ) 9>"${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-appicon.lock"

  if [ -f "$launcher_png" ] || [ -f "$win_png" ] || [ -f "${link_path}.png" ]; then
    if [ "$known" != 1 ]; then
      classes_extra+=(appicon "appicon-${app_key}")
    fi
  fi
}
dock_windows_appicon_prepare || true

focus_class="dock-win-inactive"
if [ "$focused" = "true" ]; then
  focus_class="dock-win-active"
fi

# When PNG class is present, omit glyph text so a missed CSS rule cannot flash a nerd icon.
emit_text="$icon"
if [ "${#classes_extra[@]}" -gt 0 ]; then
  emit_text=""
fi

if [ "${#classes_extra[@]}" -gt 0 ]; then
  jq -cn \
    --arg text "$emit_text" \
    --arg tooltip "$title" \
    --arg focus "$focus_class" \
    --argjson extra "$(printf '%s\n' "${classes_extra[@]}" | jq -R . | jq -s -c .)" \
    '{text:$text, tooltip:$tooltip, class:(["dock-win-hit", $focus] + $extra)}'
else
  jq -cn \
    --arg text "$icon" \
    --arg tooltip "$title" \
    --arg focus "$focus_class" \
    '{text:$text, tooltip:$tooltip, class:["dock-win-hit", $focus]}'
fi
