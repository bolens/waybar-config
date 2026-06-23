#!/usr/bin/env bash
# Regenerate per-interface network modules from data/network-interfaces.json.
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-$HOME/.config/waybar}"
. "${0%/*}/waybar-settings.sh"
manifest="$WAYBAR_HOME/data/network-interfaces.json"
settings="$WAYBAR_HOME/data/waybar-settings.json"
modules_out="$WAYBAR_HOME/modules/network.generated.jsonc"
scripts='$HOME/.config/waybar/scripts'

[ -f "$manifest" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

iface_interval=5
bw_interval=1
if [ -f "$settings" ]; then
  iface_interval="$(jq -r '.module_intervals.network_iface // .poll_intervals.network_iface // 5' "$settings")"
  bw_interval="$(jq -r '.module_intervals.network_bandwidth // .poll_intervals.network_bandwidth // 1' "$settings")"
fi

jq -n \
  --slurpfile manifest "$manifest" \
  --arg scripts "$scripts" \
  --argjson iface_interval "$iface_interval" \
  --argjson bw_interval "$bw_interval" \
  '
  ($manifest[0]) as $m
  | ($m.bond // {}) as $bond
  | ($m.bandwidth_interface // $bond.interface // "bond0") as $bw_iface
  | ($bond.interface // "bond0") as $bond_iface
  | {
      "network#bandwidthUpBytes": {
        interface: $bw_iface,
        interval: $bw_interval,
        format: "󰡡 {bandwidthUpBytes}",
        "format-ethernet": "󰡡 {bandwidthUpBytes}",
        "format-wifi": "󰡡 {bandwidthUpBytes}",
        "format-disconnected": "",
        "tooltip-format": ("↑ {bandwidthUpBytes}/s on " + $bw_iface)
      },
      "network#bandwidthDownBytes": {
        interface: $bw_iface,
        interval: $bw_interval,
        format: "󰡻 {bandwidthDownBytes}",
        "format-ethernet": "󰡻 {bandwidthDownBytes}",
        "format-wifi": "󰡻 {bandwidthDownBytes}",
        "format-disconnected": "",
        "tooltip-format": ("↓ {bandwidthDownBytes}/s on " + $bw_iface)
      },
      "network#bond": {
        interface: $bond_iface,
        "format-ethernet": ($bond["format-ethernet"] // "󰓟"),
        "format-disconnected": ($bond["format-disconnected"] // "󰓟"),
        "tooltip-format": ($bond["tooltip-format"] // "Bond: {ipaddr}/{cidr} (Slaves: {ifname})"),
        "tooltip-format-ethernet": ($bond["tooltip-format-ethernet"] // ("Bonded: {ipaddr}/{cidr}\nSlaves: {ifname}")),
        "tooltip-format-disconnected": ($bond["tooltip-format-disconnected"] // ("Disconnected\n" + $bond_iface)),
        "on-click": ("python3 " + $scripts + "/ethernet-popup.py " + $bond_iface),
        "on-click-right": ("python3 " + $scripts + "/ethernet-popup.py " + $bond_iface),
        "on-click-middle": ("python3 " + $scripts + "/ethernet-popup.py " + $bond_iface)
      }
    }
    + (
      ($m.interfaces // [])
      | map(
          . as $iface
          | {
              key: ("custom/" + $iface.id),
              value: {
                format: "{}",
                "return-type": "json",
                interval: $iface_interval,
                exec: ($scripts + "/network-interface-status.sh " + $iface.interface),
                "on-click": (
                  if $iface.type == "wifi" then
                    ($scripts + "/wifi-click.sh list " + $iface.interface)
                  else
                    ("python3 " + $scripts + "/ethernet-popup.py " + $iface.interface)
                  end
                ),
                "on-click-right": (
                  if $iface.type == "wifi" then
                    ($scripts + "/wifi-click.sh manage " + $iface.interface)
                  else
                    ("python3 " + $scripts + "/ethernet-popup.py " + $iface.interface)
                  end
                ),
                "on-click-middle": (
                  if $iface.type == "wifi" then
                    ($scripts + "/wifi-click.sh toggle")
                  else
                    ("python3 " + $scripts + "/ethernet-popup.py " + $iface.interface)
                  end
                )
              }
            }
        )
      | from_entries
    )
  ' | jq -c '.' >"$modules_out"
