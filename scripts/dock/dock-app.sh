#!/usr/bin/env bash
# dock-app.sh <app_id> <action>
# action: left | middle | right
# Hyprland + KDE Plasma (Wayland). Launches are detached via app-open.sh.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

APP_ID="${1:-}"
ACTION="${2:-}"

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
manifest="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/dock-apps.json"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "Dock" "$1" || true
}

if [ -z "$APP_ID" ] || [ ! -f "$manifest" ]; then
  notify "Unknown dock app: ${APP_ID:-<missing>}"
  exit 1
fi

app_json="$(jq -c --arg id "$APP_ID" '.[$id] // empty' "$manifest")"
if [ -z "$app_json" ] || [ "$app_json" = "null" ]; then
  notify "Unknown app: $APP_ID"
  exit 1
fi

LAUNCH_CMD="$(jq -r '.launch // empty' <<<"$app_json")"
LAUNCH_SHELL="$(jq -r '.launch_shell // empty' <<<"$app_json")"
LAUNCH_NEW_CMD="$(jq -r '.launch_new // empty' <<<"$app_json")"
LAUNCH_NEW_SHELL="$(jq -r '.launch_new_shell // empty' <<<"$app_json")"
WM_CLASSES="$(jq -c '.wm_classes // []' <<<"$app_json")"
PROCESS_NAMES="$(jq -c '.process_names // []' <<<"$app_json")"

run_launch() {
  local shell_cmd="$1"
  local cmd="$2"

  if [ -n "$shell_cmd" ]; then
    "$WAYBAR_SCRIPTS/tools/app-open.sh" --shell "$shell_cmd"
    return
  fi
  if [ -n "$cmd" ]; then
    # shellcheck disable=SC2086
    "$WAYBAR_SCRIPTS/tools/app-open.sh" $cmd
    return
  fi
  notify "No launch command configured for $APP_ID"
  exit 1
}

launch_detached() {
  local lock_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
  local lock_file="$lock_dir/${APP_ID}.launch.lock"
  mkdir -p "$lock_dir"

  (
    flock -n 9 || exit 0
    run_launch "$LAUNCH_SHELL" "$LAUNCH_CMD"
  ) 9>"$lock_file"
}

launch_new_detached() {
  if [ -n "$LAUNCH_NEW_SHELL" ]; then
    run_launch "$LAUNCH_NEW_SHELL" ""
  elif [ -n "$LAUNCH_NEW_CMD" ]; then
    run_launch "" "$LAUNCH_NEW_CMD"
  else
    run_launch "$LAUNCH_SHELL" "$LAUNCH_CMD"
  fi
}

class_matches() {
  local value="${1:-}"
  local class
  local norm_value
  norm_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r class; do
    [ -n "$class" ] || continue
    class="$(printf '%s' "$class" | tr '[:upper:]' '[:lower:]')"
    if [ "$norm_value" = "$class" ]; then
      return 0
    fi
    if [[ "$norm_value" == *" - ${class}" ]] || [[ "$norm_value" == "${class} - "* ]]; then
      return 0
    fi
    if [ "${#class}" -gt 4 ] && [[ "$norm_value" == *"$class"* ]]; then
      return 0
    fi
  done < <(jq -r '.[]' <<<"$WM_CLASSES")
  return 1
}

process_running() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if pgrep -x "$name" >/dev/null 2>&1; then
      return 0
    fi
    if pgrep -f "$name" >/dev/null 2>&1; then
      return 0
    fi
  done < <(jq -r '.[]' <<<"$PROCESS_NAMES")
  return 1
}

list_windows_hyprland() {
  command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
  hyprctl clients -j 2>/dev/null | jq -r --argjson classes "$WM_CLASSES" '
    def norm: ascii_downcase;
    def matches($client):
      ($classes | map(norm)) as $cls |
      ([$client.class, $client.initialClass] | map(. // "" | norm)) as $wcs |
      any($wcs[]; . as $w | any($cls[]; . == $w or (length > 4 and ($w | contains(.)))));
    [.[] | select(matches(.))] | sort_by(.focusHistoryID) | reverse | .[].address
  '
}

focus_hyprland() {
  mapfile -t win_ids < <(list_windows_hyprland)
  if [ "${#win_ids[@]}" -eq 0 ]; then
    return 1
  fi
  hyprctl dispatch focuswindow "address:${win_ids[0]}" >/dev/null 2>&1
}

close_hyprland() {
  mapfile -t win_ids < <(list_windows_hyprland)
  if [ "${#win_ids[@]}" -eq 0 ]; then
    return 1
  fi
  hyprctl dispatch closewindow "address:${win_ids[0]}" >/dev/null 2>&1
}

kde_window_entries() {
  command -v qdbus6 >/dev/null 2>&1 || return 0
  local raw
  raw="$(timeout 1 qdbus6 --literal org.kde.KWin /WindowsRunner org.kde.krunner1.Match windows 2>/dev/null || true)"
  [ -n "$raw" ] || return 0

  while IFS=$'\t' read -r id title app; do
    if class_matches "$title" || class_matches "$app"; then
      printf '%s\t%s\t%s\n' "$id" "$title" "$app"
    fi
  done < <(printf '%s\n' "$raw" | \
    sed -E 's/\[Argument: \(sssida\{sv\}\) /\n/g' | \
    sed -n -E 's/^"(0_\{[^"]+\})",[[:space:]]*"([^"]*)",[[:space:]]*"([^"]*)",[[:space:]]*100,[[:space:]]*1.*/\1\t\2\t\3/p')
}

list_windows_kde() {
  kde_window_entries | cut -f1
}

kde_close_match_classes() {
  local app_field="${1:-}"
  jq -cn \
    --arg app "$app_field" \
    --argjson wm "$WM_CLASSES" \
    --argjson proc "$PROCESS_NAMES" \
    '[($app | select(length > 0)), ($proc[]?), ($wm[]?)]
      | map(ascii_downcase)
      | unique
      | map(select(length > 0))'
}

kde_close_via_script() {
  local classes_json="${1:-[]}"
  local script_dir_kde="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
  local plugin_name="waybar-close-${APP_ID}-$$"
  local script_file="$script_dir_kde/close-window-${plugin_name}.js"
  local targets_js
  mkdir -p "$script_dir_kde"

  [ "$(jq 'length' <<<"$classes_json")" -gt 0 ] || return 1

  targets_js="$(jq -r 'map("\"" + . + "\"") | join(", ")' <<<"$classes_json")"

  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin_name" >/dev/null 2>&1 || true

  cat >"$script_file" <<EOF
var targets = [${targets_js}];
var closed = false;
for (var i = workspace.stackingOrder.length - 1; i >= 0 && !closed; i--) {
  var w = workspace.stackingOrder[i];
  var cls = String(w.resourceClass || "").toLowerCase();
  for (var t = 0; t < targets.length; t++) {
    var target = targets[t];
    if (
      target.length > 0
      && (
        cls === target
        || cls.indexOf(target) >= 0
        || target.indexOf(cls) >= 0
      )
    ) {
      w.closeWindow();
      closed = true;
      break;
    }
  }
}
EOF

  if ! timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$script_file" "$plugin_name" >/dev/null 2>&1; then
    rm -f "$script_file"
    return 1
  fi

  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
  sleep 0.1
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin_name" >/dev/null 2>&1 || true
  rm -f "$script_file"
  return 0
}

close_kde() {
  local before after classes_json
  before="$(kde_window_entries | wc -l)"
  [ "$before" -gt 0 ] || return 1

  local id title app
  IFS=$'\t' read -r id title app <<< "$(kde_window_entries | head -1)"

  classes_json="$(kde_close_match_classes "$app")"
  kde_close_via_script "$classes_json" || true
  sleep 0.2
  after="$(kde_window_entries | wc -l)"
  [ "$after" -lt "$before" ]
}

focus_kde() {
  mapfile -t win_ids < <(list_windows_kde)
  if [ "${#win_ids[@]}" -eq 0 ]; then
    return 1
  fi
  timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "${win_ids[0]}" "" >/dev/null 2>&1 || true
}

has_windows() {
  case "$1" in
    hyprland)
      [ -n "$(list_windows_hyprland | head -1 || true)" ]
      ;;
    kde)
      [ -n "$(list_windows_kde | head -1 || true)" ]
      ;;
    *)
      false
      ;;
  esac
}

focus_window() {
  case "$1" in
    hyprland) focus_hyprland ;;
    kde) focus_kde ;;
    *) return 1 ;;
  esac
}

close_window() {
  case "$1" in
    hyprland) close_hyprland ;;
    kde) close_kde ;;
    *) return 1 ;;
  esac
}

session="$(detect_compositor)"
case "$session" in
  hyprland|kde) ;;
  *)
    notify "Unsupported compositor session"
    exit 1
    ;;
esac

case "$ACTION" in
  left)
    if has_windows "$session"; then
      focus_window "$session" || true
    else
      launch_detached
    fi
    ;;
  middle)
    launch_new_detached
    ;;
  right)
    if has_windows "$session"; then
      close_window "$session" || true
    elif process_running; then
      notify "No open window to close for $APP_ID"
    else
      notify "No running instance of $APP_ID"
    fi
    ;;
  *)
    notify "Unknown action: $ACTION"
    exit 1
    ;;
esac
