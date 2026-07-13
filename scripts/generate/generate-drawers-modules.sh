#!/usr/bin/env bash
# Drawer handle modules (custom/*-drawer) + tooltip-format from group contents.
# Settings drawer side keys map via drawer_group() to Waybar group ids — see jq below.
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
    # Settings drawer side keys (desk, media, …) ≠ Waybar group ids
    # (desk-controls, media, …); this map bridges SoT names → group/*.
    {
      desk: "desk-controls",
      devices: "devices",
      tray: "tray-apps",
      media: "media",
      net: "net",
      tools: "tools",
      infra: "infra",
      hardware: "hardware",
      cooling: "cooling",
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
      "custom/album-art": "Album art",
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
      "custom/pomodoro": "Pomodoro",
      "custom/cava": "Visualizer",
      "custom/homelab": "Homelab",
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
      "custom/stats-carousel": "Stats",
      "custom/nvme": "NVMe",
      "custom/psu": "PSU",
      "custom/fans": "Fans",
      "custom/liquidctl": "Liquidctl",
      "custom/coolercontrol": "CoolerControl",
      "custom/openlinkhub": "OpenLinkHub",
      "custom/lock": "Lock",
      "custom/power-menu": "Power menu",
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

  def insert_album_art($mods):
    # Keep in sync with generate-settings.sh build_groups_json (same transform for drawer tooltips).
    if (($s[0].visual.album_art.enabled // false) == true) then
      if (($mods | index("custom/album-art")) != null) then $mods
      else
        ($mods | index("custom/mpris")) as $i
        | if $i != null then
            ($mods[:$i] + ["custom/album-art"] + $mods[$i:])
          else
            ($mods | index("mpris")) as $j
            | if $j != null then
                ($mods[:$j] + ["custom/album-art"] + $mods[$j:])
              else
                $mods + ["custom/album-art"]
              end
          end
      end
    else
      $mods
    end;

  def apply_cava_placement($mods):
    # jq `//` treats false as missing — use == false, not `enabled // true`.
    (($s[0].cava.enabled == false) | not) as $on
    | (($s[0].cava.placement // "drawer") | tostring) as $place
    | if ($mods | index("custom/cava")) == null then $mods
      elif ($on | not) then
        ($mods | map(select(. != "custom/cava")))
      elif $place == "inline" then
        (["custom/cava"] + ($mods | map(select(. != "custom/cava"))))
      else
        $mods
      end;

  def apply_stats_carousel($mods):
    # Keep drawer + non-metric modules; bind . as $m before index (see generate-settings.sh).
    if (($s[0].visual.stats_carousel.enabled // false) != true) then $mods
    else
      ["custom/cpu", "custom/memory", "custom/disk", "custom/gpu"] as $hw
      | ($mods | map(select(. as $m | $hw | index($m) != null)) | length) as $n
      | if $n == 0 then $mods
        else
          ($mods | to_entries | map(select(.value as $v | $hw | index($v) != null)) | .[0].key // 0) as $at
          | ($mods[:$at] | map(select(. as $m | $hw | index($m) == null)))
            + ["custom/stats-carousel"]
            + ($mods[$at:] | map(select(. as $m | $hw | index($m) == null)))
        end
    end;

  def group_modules($g):
    ($s[0].groups[$g].modules // []) as $mods
    | if $g == "media" then apply_cava_placement(insert_album_art($mods))
      elif $g == "hardware" then apply_stats_carousel($mods)
      else $mods
      end;

  def drawer_contents($key):
    if $key == "dock" then
      if ($dock | length) > 0 then
        ($dock[0] | to_entries | map(.value.tooltip // .key) | map(split(" — ")[0] | split(" - ")[0]))
      else
        ["Pinned apps"]
      end
    else
      (drawer_group($key) as $g
        | group_modules($g)
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
    # Bottom-bar drawers (Plasma): tall "Contains:" lists render below the bar and
    # clip off-screen (Waybar#3356). Keep a short tip; open the drawer for contents.
    | (
        ["dock", "tools", "infra", "security", "hardware", "cooling"] as $bottom
        | if ($bottom | index($key)) != null then
            [$title, "Click to toggle"] | join("\n")
          else
            (
              [$title]
              + (if ($items | length) > 0 then
                  ["Contains: " + ($items | join(" · "))]
                else
                  []
                end)
              + ["Click to toggle"]
            ) | join("\n")
          end
      );

  # Waybar tooltips use Pango markup — bare & breaks parsing (Gtk-WARNING).
  def pango_escape:
    gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");

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
          "tooltip-format": ($tip | pango_escape | gsub("\\{"; "{{") | gsub("\\}"; "}}"))
        }
      };

  [
    drawer("desk"; "desk-drawer"),
    drawer("devices"; "devices-drawer"),
    drawer("dock"; "dock-drawer"),
    drawer("tray"; "tray-drawer"),
    drawer("media"; "media-drawer"),
    drawer("net"; "net-drawer"),
    drawer("tools"; "tools-drawer"),
    drawer("infra"; "infra-drawer"),
    drawer("hardware"; "hardware-drawer"),
    drawer("cooling"; "cooling-drawer"),
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
