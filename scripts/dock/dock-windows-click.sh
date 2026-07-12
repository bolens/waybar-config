#!/usr/bin/env bash
# Per-slot dock-windows actions (no rofi — active-window module owns the picker).
# Usage: dock-windows-click.sh <focus|close|cycle|close-focused> [slot] [OUTPUT]
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

mode="${1:-focus}"
slot_or_out="${2:-}"
maybe_out="${3:-}"

slot=""
output_arg=""
case "$mode" in
  focus | close)
    slot="$slot_or_out"
    output_arg="$maybe_out"
    ;;
  cycle | close-focused | activate)
    # activate kept as alias of cycle for old bindings
    output_arg="$slot_or_out"
    ;;
  *)
    output_arg="$slot_or_out"
    ;;
esac

# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=dock-windows-kde-lib.sh
. "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.sh"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

# on-click does not get WAYBAR_OUTPUT_NAME from Waybar — resolve via argv/env/active output.
WAYBAR_OUTPUT_NAME="$(dock_windows_resolve_output "$output_arg")"
export WAYBAR_OUTPUT_NAME

state_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
state_file="$state_dir/index"
mkdir -p "$state_dir"

# Prefer the window id that slot-status last rendered for this output+slot.
slot_row_from_bind() {
  local bind
  bind="$(dock_windows_read_slot_bind "${1:-}" "${WAYBAR_OUTPUT_NAME:-}" 2>/dev/null || true)"
  [ -n "$bind" ] || return 1
  printf '%s' "$bind"
}

# Write expected active title so the highlight updates before the KWin listener flushes.
optimistic_active_title() {
  local title="$1"
  local cache_dir safe
  [ -n "$title" ] || return 0
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
  mkdir -p "$cache_dir"
  # Match kde_listener.titles.clean_title (strip browser suffixes, collapse space).
  title=$(printf '%s' "$title" | tr '\n\t' '  ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')
  title=$(printf '%s' "$title" | sed -E \
    -e 's/ - Mozilla Firefox$//' \
    -e 's/ - Zen Browser$//' \
    -e 's/ - Google Chrome$//' \
    -e 's/ - Floorp$//' \
    -e 's/ - Chromium$//' \
    -e 's/ - Brave$//' \
    -e 's/ - Vivaldi$//')
  printf '%s' "$title" >"$cache_dir/active-window-title.raw"
  if [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
    safe=$(printf '%s' "$WAYBAR_OUTPUT_NAME" | sed 's/[^A-Za-z0-9_-]/_/g')
    printf '%s' "$title" >"$cache_dir/active-window-title-${safe}.raw"
  fi
}

signal_dock() {
  # Focus-only: keep list cache; slots recompute highlight from active title.
  "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" --force --focus-only >/dev/null 2>&1 || true
}

signal_dock_full() {
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
  rm -f "$cache_dir"/dock-windows-list.json "$cache_dir"/dock-windows-list.*.json 2>/dev/null || true
  "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" --force >/dev/null 2>&1 || true
}

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "Dock" "$1" || true
}

list_json() {
  "$WAYBAR_SCRIPTS/dock/dock-windows-query.sh" "${WAYBAR_OUTPUT_NAME:-}" 2>/dev/null || echo '[]'
}

# Activate a KWin window by caption and/or internal UUID.
kde_activate_window() {
  local target_uuid="${1:-}"
  local target_caption="${2:-}"
  local target_class="${3:-}"
  local script_dir plugin script
  script_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
  plugin="waybar-dock-win-focus-$$-$RANDOM"
  script="$script_dir/${plugin}.js"
  mkdir -p "$script_dir"

  # Escape for JS string literals
  local js_uuid js_cap js_cls
  js_uuid=$(printf '%s' "$target_uuid" | sed 's/\\/\\\\/g; s/"/\\"/g')
  js_cap=$(printf '%s' "$target_caption" | sed 's/\\/\\\\/g; s/"/\\"/g')
  js_cls=$(printf '%s' "$target_class" | tr '[:upper:]' '[:lower:]' | sed 's/\\/\\\\/g; s/"/\\"/g')

  cat >"$script" <<EOF
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
// 1) Exact caption match (slot title) — most precise for the clicked glyph.
if (targetCap.length > 0) {
  for (var i = workspace.stackingOrder.length - 1; i >= 0 && !activated; i--) {
    var w = workspace.stackingOrder[i];
    if (String(w.caption || "") === targetCap) {
      activate(w);
      activated = true;
    }
  }
}
// 2) internalId / uuid when WindowsRunner id aligns with KWin.
if (!activated && targetBare.length > 0) {
  for (var j = workspace.stackingOrder.length - 1; j >= 0 && !activated; j--) {
    var w2 = workspace.stackingOrder[j];
    var iid = String(w2.internalId || "");
    var bare = iid.replace(/[{}]/g, "");
    if (iid === targetUuid || bare === targetBare) {
      activate(w2);
      activated = true;
    }
  }
}
// 3) Exact resourceClass (last resort; may pick wrong window of same app).
if (!activated && targetCls.length > 0) {
  for (var k = workspace.stackingOrder.length - 1; k >= 0 && !activated; k--) {
    var w3 = workspace.stackingOrder[k];
    if (String(w3.resourceClass || "").toLowerCase() === targetCls) {
      activate(w3);
      activated = true;
    }
  }
}
EOF
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin" >/dev/null 2>&1 || true
  if ! timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$script" "$plugin" >/dev/null 2>&1; then
    rm -f "$script"
    return 1
  fi
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
  timeout 2 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$plugin" >/dev/null 2>&1 || true
  rm -f "$script"
  return 0
}

focus_id() {
  local id="$1"
  local title="${2:-}"
  local app="${3:-}"
  local session uuid
  session="$(detect_compositor)"
  [ -n "$id" ] || return 0

  if [ "$session" = "hyprland" ]; then
    hyprctl dispatch focuswindow "address:$id" >/dev/null 2>&1 || true
    (
      sleep 0.1
      hyprctl dispatch focuswindow "address:$id" >/dev/null 2>&1 || true
    ) &
    return 0
  fi

  if [ "$session" != "kde" ]; then
    return 0
  fi

  uuid="$(python3 -c "from importlib.util import spec_from_file_location, module_from_spec; s=spec_from_file_location('m','$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.py'); m=module_from_spec(s); s.loader.exec_module(m); print(m.runner_id_to_uuid('$id') or '')" 2>/dev/null || true)"

  kde_activate_window "$uuid" "$title" "$app" || true
  timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "$id" "" >/dev/null 2>&1 || true
  (
    sleep 0.08
    kde_activate_window "$uuid" "$title" "$app" || true
  ) &
}

close_id() {
  local id="$1"
  local session
  session="$(detect_compositor)"
  if [ "$session" = "hyprland" ]; then
    if [ -n "$id" ]; then
      hyprctl dispatch closewindow "address:$id" >/dev/null 2>&1 || true
    else
      hyprctl dispatch killactive >/dev/null 2>&1 || true
    fi
  elif [ "$session" = "kde" ]; then
    # Focus then kill (WindowsRunner has no direct close-by-id).
    [ -n "$id" ] && focus_id "$id"
    timeout 2 qdbus6 org.kde.KWin /KWin org.kde.KWin.killWindow >/dev/null 2>&1 || true
  fi
}

session="$(detect_compositor)"
case "$session" in
  hyprland | kde) ;;
  *)
    notify "Window dock unsupported in this session"
    exit 0
    ;;
esac

if [ "$session" = "kde" ] && ! dock_windows_kde_has_qdbus; then
  notify "Install qt6-tools (qdbus6)"
  exit 0
fi

case "$mode" in
  focus)
    if [ -z "$slot" ] || ! [[ "$slot" =~ ^[0-9]+$ ]]; then
      exit 0
    fi
    row="$(slot_row_from_bind "$slot" || true)"
    if [ -z "$row" ]; then
      row=$(list_json | jq -c --argjson i "$slot" '.[$i] // empty')
    fi
    id=$(printf '%s' "$row" | jq -r '.id // empty')
    title=$(printf '%s' "$row" | jq -r '.title // empty')
    app=$(printf '%s' "$row" | jq -r '.app // empty')
    # Highlight first (optimistic), then focus — KWin activate is the slow part.
    optimistic_active_title "$title"
    signal_dock
    focus_id "$id" "$title" "$app"
    ;;
  close)
    if [ -z "$slot" ] || ! [[ "$slot" =~ ^[0-9]+$ ]]; then
      exit 0
    fi
    row="$(slot_row_from_bind "$slot" || true)"
    if [ -n "$row" ]; then
      id=$(printf '%s' "$row" | jq -r '.id // empty')
    else
      id=$(list_json | jq -r --argjson i "$slot" '.[$i].id // empty')
    fi
    close_id "$id"
    signal_dock_full
    ;;
  close-focused)
    close_id ""
    signal_dock_full
    ;;
  cycle | activate)
    mapfile -t ids < <(list_json | jq -r '.[].id // empty')
    if [ "${#ids[@]}" -eq 0 ]; then
      notify "No open windows"
      exit 0
    fi
    idx=0
    if [ -f "$state_file" ]; then
      idx="$(cat "$state_file" 2>/dev/null || echo 0)"
    fi
    idx=$(((idx + 1) % ${#ids[@]}))
    printf '%s' "$idx" >"$state_file.tmp.$$"
    mv -f "$state_file.tmp.$$" "$state_file"
    optimistic_active_title "$(list_json | jq -r --argjson i "$idx" '.[$i].title // empty')"
    signal_dock
    focus_id "${ids[$idx]}"
    ;;
  *)
    exit 1
    ;;
esac
