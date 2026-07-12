#!/usr/bin/env bash
# Prefer CoolerControl UI when the daemon is reachable; else fall back to hw monitors.
#
# Used as the default on-click for custom/fans and custom/liquidctl so cooling
# telemetry modules open the cooling UI when CoolerControl is up, instead of
# unrelated GPU/CPU monitors (nvtop/btop).
#
# Hermetic CI: set WAYBAR_TEST_COOLERCONTROL_UP=1|0 to force reachable/unreachable.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

action="${1:-open}"
ui_url=$(waybar_settings_get '.services.coolercontrol.ui_url' 'http://127.0.0.1:11987')
fallback_key="${2:-btop}"

coolercontrol_reachable() {
  case "${WAYBAR_TEST_COOLERCONTROL_UP:-}" in
    1 | true | TRUE | yes | YES | on | On | ON) return 0 ;;
    0 | false | FALSE | no | NO | off | Off | OFF) return 1 ;;
  esac
  command -v curl >/dev/null 2>&1 || return 1
  local base="${ui_url%/}"
  timeout 1 curl -fsS -o /dev/null --max-time 1 "${base}/" 2>/dev/null \
    || timeout 1 curl -fsS -o /dev/null --max-time 1 "${base}/status" 2>/dev/null
}

case "$action" in
  open)
    if coolercontrol_reachable; then
      exec "$WAYBAR_SCRIPTS/tools/app-open.sh" xdg-open "$ui_url"
    fi
    exec "$WAYBAR_SCRIPTS/tools/app-open-key.sh" "$fallback_key"
    ;;
  menu)
    if coolercontrol_reachable && [ -x "$WAYBAR_SCRIPTS/services/coolercontrol/coolercontrol-click.sh" ]; then
      exec "$WAYBAR_SCRIPTS/services/coolercontrol/coolercontrol-click.sh" menu
    fi
    exec "$WAYBAR_SCRIPTS/tools/app-open-key.sh" "$fallback_key"
    ;;
  *)
    printf 'Usage: %s open|menu [fallback_app_key]\n' "$0" >&2
    exit 1
    ;;
esac
