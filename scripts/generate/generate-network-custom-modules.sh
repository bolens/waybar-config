#!/usr/bin/env bash
# Domain module emitter (split from former generate-module-configs.sh).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
# Keep literal $WAYBAR_HOME so generated modules stay portable (match other generators).
scripts='$WAYBAR_HOME/scripts'

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

mod_dir="$WAYBAR_HOME/modules"
theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$mod_dir" "$theme_dir"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);
  def app_open: ($scripts + "/tools/app-open.sh");
  # Middle-click: refresh cache then signal — Waybar ignores on-click stdout.
  def sig_refresh($key; $script):
    ($script + " --refresh && " + $scripts + "/lib/waybar-signal.sh " + $key);

  {
    "custom/vpnstatus": {
      format: "{}",
      "return-type": "json",
      interval: iv("vpn"),
      signal: sig("vpn"),
      exec: ($scripts + "/network/vpn-status.sh"),
      "on-click": ("python3 " + $scripts + "/network/vpn-status-popup.py"),
      "on-click-right": (app_open + " " + (($s[0].apps.network_editor // "nm-connection-editor"))),
      "on-click-middle": sig_refresh("vpn"; $scripts + "/network/vpn-status.sh")
    },
    "custom/tailscale": {
      format: "{}",
      "return-type": "json",
      interval: iv("tailscale"),
      signal: sig("tailscale"),
      exec: ($scripts + "/network/tailscale-status.sh"),
      "on-click": (app_open + " " + ($s[0].network.tailscale_status_cmd // "ghostty -e tailscale status")),
      "on-click-right": (app_open + " xdg-open " + ($s[0].network.tailscale_admin_url // "http://100.100.100.100/")),
      "on-click-middle": sig_refresh("tailscale"; $scripts + "/network/tailscale-status.sh")
    },
    "custom/i2pd": {
      format: "{}",
      "return-type": "json",
      interval: iv("i2pd"),
      signal: sig("i2pd"),
      tooltip: true,
      exec: ($scripts + "/services/i2pd/i2pd-status.sh"),
      "on-click": ($s[0].services.i2pd.on_click // (app_open + " xdg-open " + (($s[0].services.i2pd.console_url // "http://127.0.0.1:7070/") | sub("/$"; "")))),
      "on-click-right": ($s[0].services.i2pd.on_click_right // (app_open + " systemctl restart " + ($s[0].services.i2pd.service_name // "i2pd.service"))),
      "on-click-middle": ($scripts + "/services/i2pd/i2pd-status.sh --refresh")
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq -c '.' >"$mod_dir/network-custom.generated.jsonc"
