#!/usr/bin/env bash
# Data-driven dock launcher icons and click handlers (data/dock-apps.json).
set -euo pipefail

app_id="${1:-}"
action="${2:-status}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
manifest="$WAYBAR_HOME/data/dock-apps.json"

if [ -z "$app_id" ] || [ ! -f "$manifest" ]; then
  exit 1
fi

run_detached() {
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$@" >/dev/null 2>&1 </dev/null &
    return
  fi
  "$@" >/dev/null 2>&1 &
}

# Resolve a PNG via appicon when icons.appicon.enabled; symlink for CSS background-image.
# Glyph fallback when disabled, binary missing, or resolve fails. Never embeds SVGL URLs.
dock_appicon_prepare() {
  local query path link_dir link_path size theme enabled
  classes_extra=""

  if [ ! -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
    return 0
  fi
  # shellcheck source=../lib/waybar-settings.sh
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

  enabled="$(waybar_settings_get '.icons.appicon.enabled' 'false')"
  case "$enabled" in
    true | True | TRUE | 1 | yes | Yes | YES | on | On | ON) ;;
    *) return 0 ;;
  esac

  if ! command -v appicon >/dev/null 2>&1; then
    return 0
  fi

  size="$(waybar_settings_get '.icons.appicon.size' '22')"
  theme="$(waybar_settings_get '.icons.appicon.theme' 'dark')"
  query="$(jq -r --arg id "$app_id" '
    .[$id]
    | if . == null then empty
      else (.appicon // .launch // $id)
      end
  ' "$manifest")"
  [ -n "$query" ] || query="$app_id"

  path="$(appicon resolve --format png --size "$size" --theme "$theme" "$query" 2>/dev/null || true)"
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    return 0
  fi

  link_dir="$WAYBAR_HOME/theme/dock-appicons"
  link_path="$link_dir/$app_id"
  mkdir -p "$link_dir"
  ln -sfn "$path" "$link_path" 2>/dev/null || true
  if [ -e "$link_path" ]; then
    classes_extra="appicon"
  fi
}

case "$action" in
  status)
    # Extract properties in a single jq process (tsv format: icon, tooltip, process_names)
    IFS=$'\t' read -r icon tooltip proc_list < <(jq -r --arg id "$app_id" '
      .[$id]
      | if . == null then empty
        else [
          (.icon // ""),
          (.tooltip // ""),
          ((.process_names // []) | join(","))
        ] | @tsv
        end
    ' "$manifest")

    is_running="false"
    if [ -n "$proc_list" ] && [ "$proc_list" != "null" ]; then
      # Split comma-separated process names
      IFS=',' read -ra proc_arr <<<"$proc_list"
      for name in "${proc_arr[@]}"; do
        if [ -n "$name" ] && pgrep -x "$name" >/dev/null 2>&1; then
          is_running="true"
          break
        fi
      done
    fi

    class="ready"
    if [ "$is_running" = "true" ]; then
      class="running"
    fi

    classes_extra=""
    dock_appicon_prepare
    if [ -n "${classes_extra:-}" ]; then
      class="$class $classes_extra"
    fi

    jq -cn \
      --arg text "${icon:-}" \
      --arg tooltip "${tooltip:-}" \
      --arg class "$class" \
      '{text:$text, tooltip:$tooltip, class:$class}'
    ;;
  click)
    field="${3:-on-click}"
    case "$field" in
      on-click) click_action="left" ;;
      on-click-middle) click_action="middle" ;;
      on-click-right) click_action="right" ;;
      left | middle | right) click_action="$field" ;;
      *)
        exit 1
        ;;
    esac
    run_detached "$script_dir/dock-app.sh" "$app_id" "$click_action"
    # Refresh dock app running indicators (dedicated signal; not dock_windows).
    sig=26
    if [ -f "$WAYBAR_HOME/data/waybar-settings.json" ] \
      && command -v jq >/dev/null 2>&1; then
      sig="$(jq -r '.signals.dock_apps // 26' "$WAYBAR_HOME/data/waybar-settings.json")"
    fi
    (
      sleep 1
      "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig" >/dev/null 2>&1 || true
    ) &
    ;;
  *)
    exit 1
    ;;
esac
