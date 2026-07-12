#!/usr/bin/env bash
# Shared window list for dock-windows slots (cached briefly for consistent slot views).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=dock-windows-kde-lib.sh
. "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.sh"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

output_arg="${1:-${WAYBAR_OUTPUT_NAME:-}}"
if [ -n "$output_arg" ]; then
  export WAYBAR_OUTPUT_NAME="$output_arg"
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
mkdir -p "$cache_dir"
dock_windows_load_icon_map

suffix=""
if dock_windows_per_output_enabled && [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
  suffix="$(dock_windows_cache_suffix "$WAYBAR_OUTPUT_NAME")"
fi
list_cache="$cache_dir/dock-windows-list${suffix}.json"
ttl=1

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

title_is_focused() {
  local title="$1"
  local tn an
  tn=$(printf '%s' "$title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  an="$active_title"
  [ -n "$an" ] || return 1
  [ "$tn" = "$an" ] && return 0
  [[ "$tn" == *"$an"* ]] && return 0
  [[ "$an" == *"$tn"* ]] && return 0
  return 1
}

emit_row() {
  local id="$1" title="$2" app="$3" focused="$4"
  local icon
  icon="$(dock_windows_icon_for "$title" "$app")"
  jq -cn \
    --arg id "$id" \
    --arg title "$title" \
    --arg app "$app" \
    --arg icon "$icon" \
    --argjson focused "$focused" \
    '{id:$id, title:$title, app:$app, icon:$icon, focused:$focused}'
}

build_list() {
  local session
  session="$(detect_compositor)"

  if [ "$session" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local clients first=1 id title app focused
    clients="$(hyprctl clients -j 2>/dev/null || echo '[]')"
    if dock_windows_per_output_enabled && [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
      clients=$(printf '%s' "$clients" | jq -c --arg o "$WAYBAR_OUTPUT_NAME" \
        '[.[] | select(($o == "") or ((.monitor // "") == $o))]')
    fi
    printf '['
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      id=$(printf '%s' "$row" | jq -r '.id // empty')
      title=$(printf '%s' "$row" | jq -r '.title // empty')
      app=$(printf '%s' "$row" | jq -r '.app // empty')
      focused=$(printf '%s' "$row" | jq -r 'if .focused then "true" else "false" end')
      [ -n "$id" ] || continue
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      emit_row "$id" "$title" "$app" "$focused"
    done < <(
      printf '%s' "$clients" | jq -c --arg at "$active_title" '
        [.[]
          | select((.title // "") != "" or (.class // "") != "")
          | {
              id: (.address // ""),
              title: ((.title // "") | sub("^\\[0_\\{[^]]+}] ?"; "")),
              app: (.class // ""),
              focused: (
                (.focused == true)
                or (
                  ($at != "")
                  and (
                    (((.title // "") | sub("^\\[0_\\{[^]]+}] ?"; "")) == $at)
                    or (((.title // "") | sub("^\\[0_\\{[^]]+}] ?"; "")) | contains($at))
                    or ($at | contains(((.title // "") | sub("^\\[0_\\{[^]]+}] ?"; ""))))
                  )
                )
              )
            }
        ][]
      '
    )
    printf ']\n'
    return 0
  fi

  if [ "$session" = "kde" ]; then
    if ! dock_windows_kde_has_qdbus; then
      printf '[]\n'
      return 0
    fi
    local filter_out="" i n id title app t a focused first=1
    local -a click_entries=() status_entries=()
    if dock_windows_per_output_enabled && [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
      filter_out="$WAYBAR_OUTPUT_NAME"
    fi
    mapfile -t click_entries < <(
      if [ -n "$filter_out" ]; then
        dock_windows_kde_list --output "$filter_out" --mode click || true
      else
        dock_windows_kde_list --mode click || true
      fi
    )
    mapfile -t status_entries < <(
      if [ -n "$filter_out" ]; then
        dock_windows_kde_list --output "$filter_out" --mode status || true
      else
        dock_windows_kde_list --mode status || true
      fi
    )
    n=${#click_entries[@]}
    printf '['
    for ((i = 0; i < n; i++)); do
      id="${click_entries[$i]%%|*}"
      title="${click_entries[$i]#*|}"
      app=""
      if [ "$i" -lt "${#status_entries[@]}" ]; then
        t="${status_entries[$i]%%|*}"
        a="${status_entries[$i]#*|}"
        # Prefer status title/app when the status title matches click title.
        if [ "$t" = "$title" ] || [ -z "$title" ]; then
          [ -n "$t" ] && title="$t"
          app="$a"
        else
          # Fall back: find status row with same title.
          local se st sa
          for se in "${status_entries[@]}"; do
            st="${se%%|*}"
            sa="${se#*|}"
            if [ "$st" = "$title" ]; then
              app="$sa"
              break
            fi
          done
        fi
      fi
      [ -n "$id" ] || continue
      focused=false
      if title_is_focused "$title"; then
        focused=true
      fi
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      emit_row "$id" "$title" "$app" "$focused"
    done
    printf ']\n'
    return 0
  fi

  printf '[]\n'
}

if [ -f "$list_cache" ] && [ "$(cache_file_age "$list_cache")" -le "$ttl" ] 2>/dev/null; then
  cat "$list_cache"
  exit 0
fi

ensure_cache_writable "$list_cache"
tmp="$list_cache.tmp.$$"
if build_list >"$tmp"; then
  mv -f "$tmp" "$list_cache" 2>/dev/null || true
  if [ -f "$list_cache" ]; then
    cat "$list_cache"
  else
    cat "$tmp"
    rm -f "$tmp"
  fi
else
  rm -f "$tmp"
  printf '[]\n'
fi
