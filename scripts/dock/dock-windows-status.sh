#!/usr/bin/env bash
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# Args: [--refresh] [OUTPUT]
do_refresh=0
output_arg=""
for _a in "$@"; do
  case "$_a" in
    --refresh) do_refresh=1 ;;
    *) [ -n "$_a" ] && output_arg="$_a" ;;
  esac
done
if [ -n "$output_arg" ]; then
  export WAYBAR_OUTPUT_NAME="$output_arg"
fi
: "${WAYBAR_OUTPUT_NAME:=}"

# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=dock-windows-kde-lib.sh
. "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_suffix=""
if dock_windows_per_output_enabled && [ -n "$WAYBAR_OUTPUT_NAME" ]; then
  cache_suffix="$(dock_windows_cache_suffix "$WAYBAR_OUTPUT_NAME")"
fi
cache_file="$cache_dir/dock-windows-status${cache_suffix}.json"
lock_dir="$cache_dir/dock-windows-status${cache_suffix}.lock.d"
ttl="$(waybar_module_interval dock_windows 120)"
stale_lock_ttl=180

mkdir -p "$cache_dir"

trim_title() {
  local s="$1"
  local max="${2:-24}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  s="$(echo "$s" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s' "${s:0:$max}"
  fi
}

emit_json() {
  local text="$1"
  local tooltip="$2"
  local class="$3"
  jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" '{text:$text, tooltip:$tooltip, class:$class}'
}

hypr_clients_filtered() {
  local clients_json="$1"
  local out="$2"
  if dock_windows_per_output_enabled && [ -n "$out" ]; then
    printf '%s' "$clients_json" | jq -c --arg o "$out" \
      '[.[] | select(($o == "") or ((.monitor // "") == $o))]'
  else
    printf '%s' "$clients_json"
  fi
}

generate_json() {
  # shellcheck source=compositor-session.sh
  . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
  local session
  session="$(detect_compositor)"
  local icons=0
  if dock_windows_icons_enabled; then
    icons=1
    dock_windows_load_icon_map
  fi

  if [ "$session" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local clients_json count tooltip_list text shown title class icon focused_title
    clients_json="$(hyprctl clients -j 2>/dev/null || echo '[]')"
    clients_json="$(hypr_clients_filtered "$clients_json" "$WAYBAR_OUTPUT_NAME")"
    count="$(printf '%s' "$clients_json" | jq '[.[] | select((.title // "") != "" or (.class // "") != "")] | length')"

    if [ "${count:-0}" -eq 0 ]; then
      emit_json "" "No open windows" "disabled"
      return 0
    fi

    tooltip_list="$(printf '%s' "$clients_json" | jq -r '
      [.[] | select((.title // "") != "" or (.class // "") != "")
        | (.title // .class // "")
        | sub("^\\[0_\\{[^]]+}] ?"; "")][0:20]
      | join("\n")
    ')"

    if [ "$icons" -eq 1 ]; then
      text=""
      shown=0
      while IFS=$'\t' read -r title class; do
        [ -n "$title" ] || [ -n "$class" ] || continue
        icon="$(dock_windows_icon_for "$title" "$class")"
        if [ -n "$text" ]; then
          text="$text $icon"
        else
          text="$icon"
        fi
        shown=$((shown + 1))
        [ "$shown" -ge 12 ] && break
      done < <(
        printf '%s' "$clients_json" | jq -r '
          [.[] | select((.title // "") != "" or (.class // "") != "")]
          | sort_by(.focusHistoryID // 9999)
          | .[]
          | [(.title // "" | sub("^\\[0_\\{[^]]+}] ?"; "")), (.class // "")]
          | @tsv
        '
      )
      [ -n "$text" ] || text=""
      emit_json "$text" "$tooltip_list" "active"
      return 0
    fi

    focused_title="$(printf '%s' "$clients_json" | jq -r '
      [.[] | select(.focused == true) | .title | sub("^\\[0_\\{[^]]+}] ?"; "")][0] // empty
    ')"
    if [ -z "$focused_title" ]; then
      focused_title="$(printf '%s' "$clients_json" | jq -r '
        [.[] | select((.title // "") != "")]
        | sort_by(.focusHistoryID // 9999)
        | .[0].title // empty
        | sub("^\\[0_\\{[^]]+}] ?"; "")
      ')"
    fi
    if [ -z "$focused_title" ]; then
      emit_json "" "$tooltip_list" "active"
      return 0
    fi
    emit_json "$(trim_title "$focused_title" 120)" "$tooltip_list" "active"
    return 0
  fi

  if [ "$session" = "kde" ]; then
    if ! dock_windows_kde_has_qdbus; then
      emit_json "" "Install qt6-tools (qdbus6)" "disabled"
      return 0
    fi

    local filter_out="" e t app display short text tooltip shown icon
    if dock_windows_per_output_enabled && [ -n "$WAYBAR_OUTPUT_NAME" ]; then
      filter_out="$WAYBAR_OUTPUT_NAME"
    fi

    mapfile -t entries < <(
      if [ -n "$filter_out" ]; then
        dock_windows_kde_list --output "$filter_out" --mode status || true
      else
        dock_windows_kde_list --mode status || true
      fi
    )

    if [ "${#entries[@]}" -eq 0 ]; then
      emit_json "" "No open windows" "disabled"
      return 0
    fi

    text=""
    tooltip=""
    shown=0
    for e in "${entries[@]}"; do
      t="${e%%|*}"
      app="${e#*|}"
      [ -n "$t" ] || [ -n "$app" ] || continue

      display="$t"
      if [ "${#display}" -le 1 ] && [ -n "$app" ]; then
        display="$app"
      fi
      [ -n "$display" ] || continue

      if [ "$icons" -eq 1 ]; then
        icon="$(dock_windows_icon_for "$display" "$app")"
        if [ -n "$text" ]; then
          text="$text $icon"
        else
          text="$icon"
        fi
      elif [ "$shown" -lt 4 ]; then
        short="$(trim_title "$display" 28)"
        if [ -n "$text" ]; then
          text="$text | $short"
        else
          text="$short"
        fi
      fi
      if [ "$shown" -lt 20 ]; then
        if [ -n "$tooltip" ]; then
          tooltip=$(printf '%s\n%s' "$tooltip" "$display")
        else
          tooltip="$display"
        fi
      fi
      shown=$((shown + 1))
      [ "$icons" -eq 1 ] && [ "$shown" -ge 12 ] && break
    done

    if [ "$shown" -eq 0 ]; then
      emit_json "" "No open windows" "disabled"
      return 0
    fi

    if [ "$icons" -eq 1 ]; then
      emit_json "$text" "$tooltip" "active"
    else
      emit_json " $text" "$tooltip" "active"
    fi
    return 0
  fi

  emit_json "" "Window dock unsupported in current session" "disabled"
}

if [ "$do_refresh" -eq 0 ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_json " ..." "Refreshing window list" "disabled"
  exit 0
fi

ensure_cache_writable "$cache_file"
tmp_cache="$cache_file.tmp.$$"
if generate_json >"$tmp_cache"; then
  if mv -f "$tmp_cache" "$cache_file" 2>/dev/null; then
    cat "$cache_file"
  else
    # Destination may be root-owned; emit fresh JSON and leave tmp for next attempt.
    cat "$tmp_cache"
    rm -f "$tmp_cache"
  fi
else
  rm -f "$tmp_cache"
  emit_json "" "Window dock refresh failed" "disabled"
fi
