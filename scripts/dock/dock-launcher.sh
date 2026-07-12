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

# Resolve a PNG via appicon when icons.appicon.enabled; materialize exact-size file for CSS.
# Glyph fallback when disabled, binary missing, or resolve fails. Never embeds SVGL URLs.
# Prefer an existing materialized PNG so focus/signal refreshes never drop .appicon (glyph flash).
dock_appicon_prepare() {
  local query path link_dir link_path display_size theme png
  classes_extra=()

  if [ ! -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ] \
    || [ ! -f "$WAYBAR_SCRIPTS/lib/appicon-lib.sh" ]; then
    return 0
  fi
  # shellcheck source=../lib/waybar-settings.sh
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
  # shellcheck source=../lib/appicon-lib.sh
  . "$WAYBAR_SCRIPTS/lib/appicon-lib.sh"

  waybar_appicon_enabled || return 0

  link_dir="$WAYBAR_HOME/theme/dock-appicons"
  link_path="$link_dir/$app_id"
  png="${link_path}.png"
  # Warm cache: keep .appicon on every signal/status tick without re-resolving.
  if [ -f "$png" ] || [ -e "$link_path" ]; then
    waybar_appicon_miss_clear "$app_id" || true
    classes_extra=(appicon)
    return 0
  fi

  # Recent miss → skip spawn; glyph stays until prefetch / TTL.
  if waybar_appicon_miss_fresh "$app_id"; then
    return 0
  fi

  display_size="$(waybar_settings_get '.icons.appicon.size' '18')"
  theme="$(waybar_settings_get '.icons.appicon.theme' 'dark')"
  query="$(jq -r --arg id "$app_id" '
    .[$id]
    | if . == null then empty
      else (
        .appicon
        // .launch
        // (.process_names[0] // empty)
        // (.wm_classes[0] // empty)
        // $id
      )
      end
  ' "$manifest")"
  [ -n "$query" ] || query="$app_id"

  # Hot path: --offline against ~/.cache/appicon (prefetch fills online).
  path="$(waybar_appicon_resolve "$query" "$display_size" "$theme" offline || true)"
  if [ -z "${path:-}" ] || [ ! -f "$path" ]; then
    waybar_appicon_miss_mark "$app_id" || true
    return 0
  fi

  mkdir -p "$link_dir"
  if waybar_appicon_materialize "$path" "$link_path" "$display_size"; then
    waybar_appicon_miss_clear "$app_id" || true
    classes_extra=(appicon)
  else
    waybar_appicon_miss_mark "$app_id" || true
  fi
}

case "$action" in
  status)
    # icon, display name, detail (no newlines — @tsv escapes them), process_names
    IFS=$'\t' read -r icon name detail proc_list < <(jq -r --arg id "$app_id" '
      .[$id]
      | if . == null then empty
        else
          (
            .name
            // ((.tooltip // "") | split(" — ") | .[0] | split(" - ") | .[0])
            // $id
          ) as $name
          | (
              ((.tooltip // "") | split(" — ") | if length > 1 then .[1:] | join(" — ") else "" end)
            ) as $detail
          | [
              (.icon // ""),
              $name,
              $detail,
              ((.process_names // []) | join(","))
            ] | @tsv
        end
    ' "$manifest")

    if [ -z "${name:-}" ] || [ "$name" = "null" ]; then
      name="$app_id"
    fi
    if [ -n "${detail:-}" ] && [ "$detail" != "null" ]; then
      tooltip="${name}"$'\n'"${detail}"
    else
      tooltip="$name"
    fi

    is_running="false"
    if [ -n "$proc_list" ] && [ "$proc_list" != "null" ]; then
      # Split comma-separated process names
      IFS=',' read -ra proc_arr <<<"$proc_list"
      for name_proc in "${proc_arr[@]}"; do
        if [ -n "$name_proc" ] && pgrep -x "$name_proc" >/dev/null 2>&1; then
          is_running="true"
          break
        fi
      done
    fi

    class="ready"
    if [ "$is_running" = "true" ]; then
      class="running"
    fi

    classes_extra=()
    dock_appicon_prepare || true

    emit_text="${icon:-}"
    if [ "${#classes_extra[@]}" -gt 0 ]; then
      emit_text=""
    fi

    # Waybar applies class as one token unless it is a JSON array.
    if [ "${#classes_extra[@]}" -gt 0 ]; then
      jq -cn \
        --arg text "$emit_text" \
        --arg tooltip "${tooltip:-}" \
        --arg base "$class" \
        --argjson extra "$(printf '%s\n' "${classes_extra[@]}" | jq -R . | jq -s -c .)" \
        '{text:$text, tooltip:$tooltip, class:([$base] + $extra)}'
    else
      jq -cn \
        --arg text "${icon:-}" \
        --arg tooltip "${tooltip:-}" \
        --arg class "$class" \
        '{text:$text, tooltip:$tooltip, class:$class}'
    fi
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
    # Refresh dock app running indicators + window-strip focused state.
    sig=26
    dock_sig=11
    if [ -f "$WAYBAR_HOME/data/waybar-settings.json" ] \
      && command -v jq >/dev/null 2>&1; then
      sig="$(jq -r '.signals.dock_apps // 26' "$WAYBAR_HOME/data/waybar-settings.json")"
      dock_sig="$(jq -r '.signals.dock_windows // 11' "$WAYBAR_HOME/data/waybar-settings.json")"
    fi
    (
      # Fast path: force window-strip highlight refresh as soon as focus settles.
      sleep 0.05
      if [ -x "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" ]; then
        "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" --force --focus-only >/dev/null 2>&1 || true
      else
        "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$dock_sig" >/dev/null 2>&1 || true
      fi
      # Running indicators can lag launch slightly.
      sleep 0.4
      "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig" >/dev/null 2>&1 || true
    ) &
    ;;
  *)
    exit 1
    ;;
esac
