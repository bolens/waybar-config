#!/usr/bin/env bash
# dock-app.sh <app_id> <action>
# action: left | middle | right
# Hyprland + KDE Plasma (Wayland). Launches are detached via app-open.sh.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

APP_ID="${1:-}"
ACTION="${2:-}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
manifest="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/dock-apps.json"
# shellcheck source=../lib/compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=../lib/app-open-lib.sh
. "$WAYBAR_SCRIPTS/lib/app-open-lib.sh"

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
    waybar_app_open "$cmd"
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
  # Empty WindowsRunner fields must not match via substring heuristics.
  [ -n "$value" ] || return 1
  norm_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  # Strip .desktop / reverse-DNS noise (org.kde.dolphin → dolphin).
  local bare="${norm_value%.desktop}"
  bare="${bare##*.}"
  while IFS= read -r class; do
    [ -n "$class" ] || continue
    class="$(printf '%s' "$class" | tr '[:upper:]' '[:lower:]')"
    if [ "$norm_value" = "$class" ] || [ "$bare" = "$class" ]; then
      return 0
    fi
    # Title forms: "Document — App" / "App - Document"
    if [[ "$norm_value" == *" - ${class}" ]] || [[ "$norm_value" == "${class} - "* ]] \
      || [[ "$norm_value" == *" — ${class}" ]] || [[ "$norm_value" == "${class} — "* ]]; then
      return 0
    fi
    # Only allow contains for longer tokens to avoid "code"/"zen" false positives.
    if [ "${#class}" -gt 5 ] && [[ "$norm_value" == *"$class"* ]]; then
      return 0
    fi
  done < <(jq -r '.[]' <<<"$WM_CLASSES")
  return 1
}

process_running() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # Exact process name only — pgrep -f false-positives break focus/launch.
    if pgrep -x "$name" >/dev/null 2>&1; then
      return 0
    fi
  done < <(jq -r '.[]' <<<"$PROCESS_NAMES")
  return 1
}

list_windows_hyprland() {
  command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
  # focusHistoryID 0 = currently focused / most recent — ascending puts it first.
  # Prefer exact class matches over loose contains so we do not steal unrelated windows.
  hyprctl clients -j 2>/dev/null | jq -r --argjson classes "$WM_CLASSES" '
    def norm: ascii_downcase;
    def wcs($client):
      ([$client.class, $client.initialClass] | map(. // "" | norm));
    def exact($client):
      ($classes | map(norm)) as $cls |
      any(wcs($client)[]; . as $w | any($cls[]; . == $w));
    def matches($client):
      ($classes | map(norm)) as $cls |
      any(wcs($client)[]; . as $w | any($cls[];
        . == $w
        or (length > 5 and ($w | contains(.)))
      ));
    [.[] | select(matches(.))]
    | sort_by(.focusHistoryID)
    | sort_by(exact(.) | not)
    | .[].address
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
  command -v jq >/dev/null 2>&1 || return 0
  local raw entries
  raw="$(timeout 2 qdbus6 --literal org.kde.KWin /WindowsRunner org.kde.krunner1.Match windows 2>/dev/null || true)"
  [ -n "$raw" ] || return 0

  if [ -f "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.py" ]; then
    entries="$(printf '%s\n' "$raw" | python3 "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.py" parse --json 2>/dev/null || echo '[]')"
  else
    entries='[]'
  fi

  printf '%s' "$entries" | jq -r --argjson classes "$WM_CLASSES" '
    def norm: ascii_downcase;
    def bare: ascii_downcase | sub("\\.desktop$"; "") | split(".") | .[-1];
    ($classes | map(norm)) as $cls |
    .[]?
    | select((.id // "") != "")
    | . as $w
    | (
        [($w.resourceClass // ""), ($w.app // ""), ($w.resourceName // ""), ($w.desktopFile // "")]
        | map(select(length > 0) | norm)
      ) as $fields
    | (
        $fields + ($fields | map(bare))
        | unique
      ) as $vals
    | select(any($vals[]; . as $v | any($cls[]; . == $v)))
    | "\(.id)\t\(.title // "")\t\(.resourceClass // .app // "")"
  '
}

list_windows_kde() {
  kde_window_entries | cut -f1
}

# Activate via KWin resourceClass — exact match only; writes ok file on success.
kde_focus_via_script() {
  local classes_json="${1:-[]}"
  local script_dir_kde="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
  local plugin_name="waybar-focus-${APP_ID}-$$"
  local script_file="$script_dir_kde/focus-window-${plugin_name}.js"
  local ok_file="$script_dir_kde/focus-ok-${plugin_name}"
  local targets_js
  mkdir -p "$script_dir_kde"
  rm -f "$ok_file"

  [ "$(jq 'length' <<<"$classes_json")" -gt 0 ] || return 1

  targets_js="$(jq -r 'map("\"" + . + "\"") | join(", ")' <<<"$classes_json")"

  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin_name" >/dev/null 2>&1 || true

  cat >"$script_file" <<EOF
var targets = [${targets_js}];
function bare(s) {
  s = String(s || "").toLowerCase();
  var i = s.lastIndexOf(".");
  return i >= 0 ? s.slice(i + 1) : s;
}
function matches(cls, name, desk) {
  cls = String(cls || "").toLowerCase();
  name = String(name || "").toLowerCase();
  desk = bare(desk);
  var cb = bare(cls);
  for (var t = 0; t < targets.length; t++) {
    var target = String(targets[t] || "").toLowerCase();
    if (!target) continue;
    if (cls === target || name === target || desk === target || cb === target) return true;
  }
  return false;
}
var activated = false;
for (var i = workspace.stackingOrder.length - 1; i >= 0 && !activated; i--) {
  var w = workspace.stackingOrder[i];
  if (!matches(w.resourceClass, w.resourceName, w.desktopFileName || w.desktopFile)) continue;
  if (w.minimized) w.minimized = false;
  if (typeof w.requestActivate === "function") w.requestActivate();
  else if (typeof Workspace !== "undefined") Workspace.activeWindow = w;
  else workspace.activeWindow = w;
  activated = true;
}
EOF

  if ! timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$script_file" "$plugin_name" >/dev/null 2>&1; then
    rm -f "$script_file"
    return 1
  fi

  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
  sleep 0.08
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin_name" >/dev/null 2>&1 || true
  rm -f "$script_file"
  # Script cannot easily signal bash — caller verifies via WindowsRunner / title.
  return 0
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
  IFS=$'\t' read -r id title app <<<"$(kde_window_entries | head -1)"

  classes_json="$(kde_close_match_classes "$app")"
  kde_close_via_script "$classes_json" || true
  sleep 0.2
  after="$(kde_window_entries | wc -l)"
  [ "$after" -lt "$before" ]
}

focus_kde() {
  local id title app classes_json uuid
  # Primary: WindowsRunner id matched via getWindowInfo resourceClass (exact).
  IFS=$'\t' read -r id title app <<<"$(kde_window_entries | head -1)"
  if [ -n "$id" ]; then
    # Optimistic highlight before slow KWin activate.
    if [ -n "$title" ] && [ -x "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" ]; then
      cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
      mkdir -p "$cache_dir"
      printf '%s' "$title" | tr '\n\t' '  ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//' \
        >"$cache_dir/active-window-title.raw"
      "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" --force --focus-only >/dev/null 2>&1 || true
    fi
    uuid="$(python3 -c "from importlib.util import spec_from_file_location, module_from_spec; s=spec_from_file_location('m','$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.py'); m=module_from_spec(s); s.loader.exec_module(m); print(m.runner_id_to_uuid('$id') or '')" 2>/dev/null || true)"
    kde_focus_via_uuid "$uuid" "$title" "$app" || true
    timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "$id" "" >/dev/null 2>&1 || true
    (
      sleep 0.08
      kde_focus_via_uuid "$uuid" "$title" "$app" || true
    ) &
    return 0
  fi

  # Fallback: KWin script exact resourceClass activate.
  classes_json="$(jq -cn --argjson wm "$WM_CLASSES" --argjson proc "$PROCESS_NAMES" '
    [($wm[]?), ($proc[]?)]
    | map(ascii_downcase)
    | unique
    | map(select(length > 0))
  ')"
  kde_focus_via_script "$classes_json" || return 1
  (
    sleep 0.08
    kde_focus_via_script "$classes_json" || true
  ) &
  return 0
}

kde_focus_via_uuid() {
  local target_uuid="${1:-}"
  local target_caption="${2:-}"
  local target_class="${3:-}"
  local script_dir_kde plugin_name script_file js_uuid js_cap js_cls
  script_dir_kde="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
  plugin_name="waybar-focus-uuid-${APP_ID}-$$-$RANDOM"
  script_file="$script_dir_kde/${plugin_name}.js"
  mkdir -p "$script_dir_kde"
  js_uuid=$(printf '%s' "$target_uuid" | sed 's/\\/\\\\/g; s/"/\\"/g')
  js_cap=$(printf '%s' "$target_caption" | sed 's/\\/\\\\/g; s/"/\\"/g')
  js_cls=$(printf '%s' "$target_class" | tr '[:upper:]' '[:lower:]' | sed 's/\\/\\\\/g; s/"/\\"/g')
  cat >"$script_file" <<EOF
var targetUuid = "${js_uuid}";
var targetBare = targetUuid.replace(/[{}]/g, "");
var targetCap = "${js_cap}";
var targetCls = "${js_cls}";
function activate(w) {
  if (w.minimized) w.minimized = false;
  if (typeof w.requestActivate === "function") w.requestActivate();
  else if (typeof Workspace !== "undefined") Workspace.activeWindow = w;
  else workspace.activeWindow = w;
}
var activated = false;
if (targetCap.length > 0) {
  for (var i = workspace.stackingOrder.length - 1; i >= 0 && !activated; i--) {
    var w = workspace.stackingOrder[i];
    if (String(w.caption || "") === targetCap) { activate(w); activated = true; }
  }
}
if (!activated && targetBare.length > 0) {
  for (var j = workspace.stackingOrder.length - 1; j >= 0 && !activated; j--) {
    var w2 = workspace.stackingOrder[j];
    var iid = String(w2.internalId || "");
    var bare = iid.replace(/[{}]/g, "");
    if (iid === targetUuid || bare === targetBare) { activate(w2); activated = true; }
  }
}
if (!activated && targetCls.length > 0) {
  for (var k = workspace.stackingOrder.length - 1; k >= 0 && !activated; k--) {
    var w3 = workspace.stackingOrder[k];
    if (String(w3.resourceClass || "").toLowerCase() === targetCls) { activate(w3); activated = true; }
  }
}
EOF
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin_name" >/dev/null 2>&1 || true
  if ! timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$script_file" "$plugin_name" >/dev/null 2>&1; then
    rm -f "$script_file"
    return 1
  fi
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin_name" >/dev/null 2>&1 || true
  rm -f "$script_file"
  return 0
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
  hyprland | kde) ;;
  *)
    notify "Unsupported compositor session"
    exit 1
    ;;
esac

case "$ACTION" in
  left)
    if has_windows "$session"; then
      focus_window "$session" || true
    elif process_running; then
      # WindowsRunner often leaves app=""; KWin resourceClass can still focus.
      focus_window "$session" || launch_detached
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
