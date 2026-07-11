#!/usr/bin/env bash
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
cache_file="$cache_dir/dock-windows-status.json"
lock_dir="$cache_dir/dock-windows-status.lock.d"
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

generate_json() {
  script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
  # shellcheck source=compositor-session.sh
  . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
  session="$(detect_compositor)"

  if [ "$session" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    clients_json="$(hyprctl clients -j 2>/dev/null || echo '[]')"
    fields="$(printf '%s' "$clients_json" | jq -r '[
    ([.[] | select((.title // "") != "")] | length),
    ((.[] | select(.focused == true) | .title | sub("^\\[0_\\{[^]]+}] ?"; "")) // ""),
    ([.[] | select((.title // "") != "") | .title | sub("^\\[0_\\{[^]]+}] ?"; "")][0:20] | join("\\n"))
  ] | @tsv')"
    tab=$'\t'
    old_ifs=$IFS
    IFS=$tab
    set -- $fields
    IFS=$old_ifs
    count="${1:-0}"

    if [ "$count" -eq 0 ]; then
      emit_json "" "No open windows" "disabled"
      exit 0
    fi

    focused_title="${2:-}"
    if [ -z "$focused_title" ]; then
      focused_title=""
    fi
    focused_title="$(trim_title "$focused_title" 120)"

    tooltip_list="${3:-}"
    emit_json "$focused_title" "$tooltip_list" "active"
    return 0
  fi

  if [ "$session" = "kde" ] && command -v qdbus6 >/dev/null 2>&1; then
    raw="$(timeout 1 qdbus6 --literal org.kde.KWin /WindowsRunner org.kde.krunner1.Match windows 2>/dev/null || true)"
    mapfile -t entries < <(printf '%s\n' "$raw" \
      | sed -E 's/\[Argument: \(sssida\{sv\}\) /\n/g' \
      | sed -n -E 's/^"0_\{[^"]+\}",[[:space:]]*"([^"]+)",[[:space:]]*"([^"]*)",[[:space:]]*100,[[:space:]]*1.*/\1|\2/p')

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
      [ -n "$t" ] || continue

      # Some KWin matches can expose a 1-char title; use app name for display in that case.
      display="$t"
      if [ "${#display}" -le 1 ] && [ -n "$app" ]; then
        display="$app"
      fi

      short="$(trim_title "$display" 28)"
      if [ "$shown" -lt 4 ]; then
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
    done

    emit_json " $text" "$tooltip" "active"
    return 0
  fi

  emit_json "" "Window dock unsupported in current session" "disabled"
}

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_json " ..." "Refreshing window list" "disabled"
  exit 0
fi

generate_json
