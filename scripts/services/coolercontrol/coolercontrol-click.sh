#!/usr/bin/env bash
# CoolerControl click/scroll actions for Waybar.
# Writable token: cycle/pick Modes. Read-only: notify and no-op (left-click stays open UI).
#
# Usage:
#   coolercontrol-click.sh next|prev|menu
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

action="${1:-next}"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

api_py="$WAYBAR_SCRIPTS/services/coolercontrol/coolercontrol-api.py"
api_url=$(waybar_settings_get '.services.coolercontrol.api_url' 'http://127.0.0.1:11987')
ui_user=$(waybar_settings_get '.services.coolercontrol.ui_user' 'CCAdmin')
ui_pass="${WAYBAR_CC_UI_PASS:-$(waybar_settings_get '.services.coolercontrol.ui_pass' '')}"
token="${WAYBAR_CC_TOKEN:-$(waybar_settings_get '.services.coolercontrol.token' '')}"

export WAYBAR_CC_API_URL="$api_url"
export WAYBAR_CC_UI_USER="$ui_user"
export WAYBAR_CC_UI_PASS="$ui_pass"
export WAYBAR_CC_TOKEN="$token"
# Preserve fixture dir for unit tests / offline mocks
if [ -n "${WAYBAR_CC_FIXTURE_DIR:-}" ]; then
  export WAYBAR_CC_FIXTURE_DIR
fi

notify() {
  local title="$1" body="$2"
  notify-send -a CoolerControl "$title" "$body" 2>/dev/null || true
}

signal_refresh() {
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" coolercontrol 2>/dev/null || true
  # Also force a background refresh for cache-driven modules
  "$WAYBAR_SCRIPTS/services/coolercontrol/coolercontrol-status.sh" --refresh >/dev/null 2>&1 || true
}

run_api() {
  python3 "$api_py" "$@"
}

case "$action" in
  next | prev)
    result=$(run_api cycle "$action" 2>/dev/null || true)
    if [ -z "$result" ]; then
      notify "CoolerControl" "API unavailable"
      exit 0
    fi
    err=$(printf '%s' "$result" | jq -r '.error // empty' 2>/dev/null || true)
    ok=$(printf '%s' "$result" | jq -r '.ok // false' 2>/dev/null || true)
    case "$err" in
      read_only)
        notify "CoolerControl" "Read-only token — mode switching disabled"
        exit 0
        ;;
      no_modes)
        notify "CoolerControl" "No modes configured — create some in the UI"
        exit 0
        ;;
      auth_failed)
        notify "CoolerControl" "Auth failed — check waybar-secrets"
        exit 0
        ;;
    esac
    if [ "$ok" = "true" ]; then
      name=$(printf '%s' "$result" | jq -r '.name // "mode"' 2>/dev/null || echo mode)
      notify "CoolerControl" "Mode: $name"
      signal_refresh
    else
      notify "CoolerControl" "Failed to switch mode"
    fi
    ;;
  menu)
    listed=$(run_api list-modes 2>/dev/null || true)
    if [ -z "$listed" ]; then
      notify "CoolerControl" "API unavailable"
      exit 0
    fi
    # Probe write before offering a picker that would fail
    probe=$(run_api probe-write 2>/dev/null || true)
    writable=$(printf '%s' "$probe" | jq -r '.write_access // false' 2>/dev/null || echo false)
    if [ "$writable" != "true" ]; then
      notify "CoolerControl" "Read-only token — open the UI to change modes"
      exit 0
    fi
    count=$(printf '%s' "$listed" | jq -r '.modes | length' 2>/dev/null || echo 0)
    if [ "$count" = "0" ] || [ -z "$count" ]; then
      notify "CoolerControl" "No modes configured — create some in the UI"
      exit 0
    fi

    if command -v rofi >/dev/null 2>&1; then
      width=$(waybar_settings_get '.rofi.coolercontrol.width' '320')
      lines=$(waybar_settings_get '.rofi.coolercontrol.lines' '6')
      menu=$(
        printf '%s' "$listed" | jq -r '
          . as $root
          | ($root.modes_active.current_mode_uid // "") as $cur
          | .modes[]
          | (if .uid == $cur then "* " else "  " end) + .name + "\t" + .uid
        '
      )
      selected=$(printf '%s\n' "$menu" | rofi -dmenu -i -p "CoolerControl mode" \
        -theme-str "window {width: ${width}px;}" \
        -l "$lines" || true)
      [ -z "$selected" ] && exit 0
      uid=$(printf '%s' "$selected" | awk -F'\t' '{print $NF}')
      [ -z "$uid" ] && exit 0
      result=$(run_api activate "$uid" 2>/dev/null || true)
      ok=$(printf '%s' "$result" | jq -r '.ok // false' 2>/dev/null || true)
      if [ "$ok" = "true" ]; then
        name=$(printf '%s' "$selected" | awk -F'\t' '{gsub(/^[* ]+/,"",$1); print $1}')
        notify "CoolerControl" "Mode: $name"
        signal_refresh
      else
        notify "CoolerControl" "Failed to activate mode"
      fi
    else
      # No rofi: fall back to next
      exec "$0" next
    fi
    ;;
  *)
    echo "usage: $0 next|prev|menu" >&2
    exit 1
    ;;
esac
