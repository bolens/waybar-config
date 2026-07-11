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

jq -n --slurpfile s "$settings" \
  --slurpfile dock "${WAYBAR_HOME}/data/dock-apps.json" \
  --slurpfile net "${WAYBAR_HOME}/data/network-interfaces.json" '
  def drawer_group($key):
    {
      desk: "desk-controls",
      tray: "tray-apps",
      media: "media",
      net: "net",
      tools: "tools",
      infra: "infra",
      hardware: "hardware",
      power: "power",
      privacy: "privacy",
      security: "security"
    }[$key];

  def module_label($mod):
    {
      "custom/notifications": "Notifications",
      "custom/powerprofiles": "Power profile",
      "custom/asusctl": "ASUS profile",
      "custom/brightness": "Brightness",
      "bluetooth": "Bluetooth",
      "idle_inhibitor": "Idle inhibitor",
      "custom/keyboard-layout": "Keyboard layout",
      "custom/kdeconnect": "KDE Connect",
      "custom/device-notifier": "Removable devices",
      "custom/streamdeck": "Stream Deck",
      "custom/vaults": "Vaults",
      "custom/touchpad": "Touchpad",
      "custom/device-battery": "Device battery",
      "custom/media-prev": "Previous",
      "custom/mpris": "Now playing",
      "custom/media-next": "Next",
      "pulseaudio": "Volume",
      "custom/mic": "Microphone",
      "network#bandwidthUpBytes": "Upload",
      "network#bandwidthDownBytes": "Download",
      "custom/vpnstatus": "VPN",
      "custom/tailscale": "Tailscale",
      "custom/i2pd": "i2pd",
      "network#bond": "Bond",
      "@network.interfaces": "Interfaces",
      "custom/screenshot": "Screenshot",
      "custom/screenrecord": "Screen record",
      "custom/nightlight": "Night light",
      "custom/clipboard": "Clipboard",
      "custom/colorpicker": "Color picker",
      "custom/rgb": "RGB",
      "custom/discord": "Discord",
      "custom/weather": "Weather",
      "custom/docker": "Docker",
      "custom/syncthing": "Syncthing",
      "custom/sunshine": "Sunshine",
      "custom/runtimes": "Runtimes",
      "custom/updates": "Updates",
      "custom/ups": "UPS",
      "custom/systemd": "Systemd",
      "custom/github": "GitHub",
      "custom/uptime": "Uptime",
      "custom/cpu": "CPU",
      "custom/gpu": "GPU",
      "custom/memory": "Memory",
      "custom/disk": "Disk",
      "custom/nvme": "NVMe",
      "custom/psu": "PSU",
      "custom/fans": "Fans",
      "custom/liquidctl": "Liquidctl",
      "custom/coolercontrol": "CoolerControl",
      "custom/openlinkhub": "OpenLinkHub",
      "custom/lock": "Lock",
      "custom/logout": "Logout",
      "custom/suspend": "Suspend",
      "custom/reboot": "Reboot",
      "custom/shutdown": "Shutdown",
      "custom/privacy-screenshare": "Screen share",
      "custom/privacy-webcam": "Webcam",
      "custom/privacy-audio-in": "Mic privacy",
      "custom/privacy-audio-out": "Audio privacy",
      "custom/privacy-location": "Location",
      "tray": "System tray",
      "custom/libredefender": "LibreDefender",
      "custom/chkrootkit": "chkrootkit"
    }[$mod] // (
      $mod
      | sub("^custom/"; "")
      | sub("^network#"; "")
      | sub("^group/"; "")
      | gsub("-"; " ")
    );

  def drawer_contents($key):
    if $key == "dock" then
      if ($dock | length) > 0 then
        ($dock[0] | to_entries | map(.value.tooltip // .key) | map(split(" — ")[0] | split(" - ")[0]))
      else
        ["Pinned apps"]
      end
    else
      (drawer_group($key) as $g
        | ($s[0].groups[$g].modules // [])
        | map(select(. != ("custom/" + $key + "-drawer")))
        | map(
            if . == "@network.interfaces" then
              if ($net | length) > 0 then
                (($net[0].interfaces // []) | map(.id // .interface // empty))
              else
                ["Interfaces"]
              end
            else
              [module_label(.)]
            end
          )
        | add // []
        | map(select(. != null and . != ""))
      )
    end;

  def drawer_tooltip($key):
    ($s[0].drawers.icons[$key].tooltip // ($key)) as $title
    | (drawer_contents($key)) as $items
    | (
        [$title]
        + (if ($items | length) > 0 then
            ["Contains: " + ($items | join(" · "))]
          else
            []
          end)
        + ["Click to toggle"]
      ) | join("\n");

  def drawer($key; $module):
    ($s[0].drawers.icons[$key].format // "") as $icon
    | drawer_tooltip($key) as $tip
    | {
        key: ("custom/" + $module),
        value: {
          # Static custom modules (no exec): Waybar only uses tooltip as a bool.
          # Put copy in tooltip-format so it shows; escape braces for fmt::format.
          format: $icon,
          tooltip: true,
          "tooltip-format": ($tip | gsub("\\{"; "{{") | gsub("\\}"; "}}"))
        }
      };

  [
    drawer("desk"; "desk-drawer"),
    drawer("dock"; "dock-drawer"),
    drawer("tray"; "tray-drawer"),
    drawer("media"; "media-drawer"),
    drawer("net"; "net-drawer"),
    drawer("tools"; "tools-drawer"),
    drawer("infra"; "infra-drawer"),
    drawer("hardware"; "hardware-drawer"),
    drawer("power"; "power-drawer"),
    drawer("privacy"; "privacy-drawer"),
    drawer("security"; "security-drawer")
  ] | from_entries
  + {
    idle_inhibitor: {
      format: "{icon}",
      "format-icons": {
        activation: "󰈶",
        deactivation: "󰈷"
      },
      "tooltip-format-activated": "Idle inhibitor active",
      "tooltip-format-deactivated": "Idle inhibitor inactive"
    }
  }
' | jq '.' >"$mod_dir/drawers.generated.jsonc"
