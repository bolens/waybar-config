#!/usr/bin/env bash
# Regenerate module JSONC files from data/waybar-settings.json.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
# Keep literal $WAYBAR_HOME so generated modules stay portable (match other generators).
scripts='$WAYBAR_HOME/scripts'

hour_format=$(detect_clock_format)
date_format=$(detect_date_format)
first_day=$(detect_first_weekday)

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

mod_dir="$WAYBAR_HOME/modules"
theme_dir="$WAYBAR_HOME/theme"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);
  def app($k): ($s[0].apps[$k] // "");
  def app_open: ($scripts + "/tools/app-open.sh");

  {
    "custom/notifications": {
      format: "{0}{icon}",
      "return-type": "json",
      signal: sig("notifications"),
      interval: iv("notifications"),
      escape: true,
      exec: ($scripts + "/notifications/notifications-status.sh"),
      "format-icons": {
        notification: "󰂚",
        none: "󰂜",
        "dnd-notification": "󰂛",
        "dnd-none": "󰂛",
        "inhibited-notification": "󰂛",
        "inhibited-none": "󰂛",
        "dnd-inhibited-notification": "󰂛",
        "dnd-inhibited-none": "󰂛",
        unknown: "󰂚"
      },
      "on-click": ($scripts + "/notifications/notifications-click.sh open"),
      "on-click-right": ($scripts + "/notifications/notifications-click.sh dnd"),
      "on-click-middle": ($scripts + "/notifications/notifications-click.sh settings")
    },
    "custom/screenshot": {
      format: "{}",
      "return-type": "json",
      interval: iv("screenshot"),
      exec: ($scripts + "/capture/screenshot-status.sh"),
      "on-click": ($scripts + "/capture/screenshot-click.sh select"),
      "on-click-right": ($scripts + "/capture/screenshot-click.sh full"),
      "on-click-middle": ($scripts + "/capture/screenshot-click.sh window")
    },
    "custom/screenrecord": {
      format: "{}",
      "return-type": "json",
      signal: sig("screenrecord"),
      interval: iv("screenrecord"),
      exec: ($scripts + "/capture/screenrecord-status.sh"),
      "on-click": ($scripts + "/capture/screenrecord-click.sh select"),
      "on-click-right": ($scripts + "/capture/screenrecord-click.sh full"),
      "on-click-middle": ($scripts + "/capture/screenrecord-click.sh window")
    },
    "custom/nightlight": {
      format: "{}",
      "return-type": "json",
      signal: sig("nightlight"),
      interval: iv("nightlight"),
      exec: ($scripts + "/services/desktop/nightlight-status.sh"),
      "on-click": ($scripts + "/services/desktop/nightlight-toggle.sh toggle"),
      "on-click-middle": ($scripts + "/services/desktop/nightlight-toggle.sh force_toggle"),
      "on-click-right": ($scripts + "/services/desktop/nightlight-toggle.sh settings")
    },
    "custom/clipboard": {
      format: "{0}{icon}",
      "return-type": "json",
      signal: sig("clipboard"),
      interval: iv("clipboard"),
      escape: true,
      exec: ($scripts + "/notifications/clipboard-status.sh"),
      "format-icons": {
        normal: "󰅌",
        empty: "󰅍",
        disabled: "󰅌",
        unknown: "󰅌"
      },
      "on-click": ($scripts + "/notifications/clipboard-click.sh open"),
      "on-click-right": ($scripts + "/notifications/clipboard-click.sh clear"),
      "on-click-middle": ($scripts + "/notifications/clipboard-click.sh edit")
    },
    "custom/brightness": {
      format: "{}",
      "return-type": "json",
      signal: sig("brightness"),
      interval: iv("brightness"),
      exec: (
        $scripts + "/lib/compositor-gate.sh --hide "
        + ($s[0].brightness.hide_on_compositor // "hyprland")
        + " -- " + $scripts + "/system/brightness-status.sh"
      ),
      "on-click": ($scripts + "/system/brightness-control.sh adjust -" + (($s[0].brightness.step_down // 5) | tostring)),
      "on-click-right": ($scripts + "/system/brightness-control.sh adjust +" + (($s[0].brightness.step_up // 5) | tostring)),
      "on-click-middle": ($scripts + "/system/brightness-control.sh set " + (($s[0].brightness.middle_set // 80) | tostring)),
      "on-scroll-up": ($scripts + "/system/brightness-control.sh adjust +" + (($s[0].brightness.step_up // 5) | tostring)),
      "on-scroll-down": ($scripts + "/system/brightness-control.sh adjust -" + (($s[0].brightness.step_down // 5) | tostring))
    },
    "custom/powerprofiles": {
      format: "{}",
      "return-type": "json",
      signal: sig("powerprofiles"),
      interval: iv("powerprofiles"),
      exec: ($scripts + "/system/powerprofiles-status.sh"),
      "on-click": ($scripts + "/system/powerprofiles-click.sh menu"),
      "on-click-right": ($scripts + "/system/powerprofiles-click.sh power-saver"),
      "on-click-middle": ($scripts + "/system/powerprofiles-click.sh balanced"),
      "on-scroll-up": ($scripts + "/system/powerprofiles-click.sh next"),
      "on-scroll-down": ($scripts + "/system/powerprofiles-click.sh next")
    },
    "custom/asusctl": {
      format: "{}",
      "return-type": "json",
      tooltip: true,
      signal: sig("asusctl"),
      interval: iv("asusctl"),
      exec: ($scripts + "/system/asusctl-status.sh"),
      "on-click": ($scripts + "/system/asusctl-click.sh menu"),
      "on-click-right": ($scripts + "/system/asusctl-click.sh next"),
      "on-click-middle": ($scripts + "/system/asusctl-status.sh --refresh"),
      "on-scroll-up": ($scripts + "/system/asusctl-click.sh next"),
      "on-scroll-down": ($scripts + "/system/asusctl-click.sh prev")
    },
    "custom/discord": {
      format: "{}",
      "return-type": "json",
      interval: iv("discord"),
      exec: ($scripts + "/services/apps/discord-status.sh"),
      "on-click": (app_open + " " + app("discord")),
      "on-click-right": ($scripts + "/services/apps/discord-click.sh mute"),
      "on-click-middle": ($scripts + "/services/apps/discord-click.sh deafen")
    },
    "custom/lock": {
      format: "",
      tooltip: "Lock screen",
      "on-click": ($scripts + "/system/power-click.sh lock")
    },
    "custom/logout": {
      format: "󰍃",
      tooltip: "Logout session",
      "on-click": ($scripts + "/system/power-click.sh logout")
    },
    "custom/suspend": {
      format: "󰤄",
      tooltip: "Suspend system",
      "on-click": ($scripts + "/system/power-click.sh suspend")
    },
    "custom/reboot": {
      format: "󰜉",
      tooltip: "Reboot system",
      "on-click": ($scripts + "/system/power-click.sh reboot")
    },
    "custom/shutdown": {
      format: "󰐥",
      tooltip: "Shutdown system",
      "on-click": ($scripts + "/system/power-click.sh shutdown")
    },
    "custom/kdeconnect": {
      format: "{}",
      "return-type": "json",
      signal: sig("kdeconnect"),
      interval: iv("kdeconnect"),
      exec: ($scripts + "/services/devices/kdeconnect-status.sh"),
      "on-click": ($s[0].kdeconnect.on_click // ($scripts + "/services/devices/kdeconnect-status.sh --ring")),
      "on-click-right": ($s[0].kdeconnect.on_click_right // ($scripts + "/services/devices/kdeconnect-menu.sh")),
      "on-click-middle": ($s[0].kdeconnect.on_click_middle // ($scripts + "/services/devices/kdeconnect-status.sh --refresh && " + $scripts + "/lib/waybar-signal.sh " + ((sig("kdeconnect") // 18) | tostring)))
    },
    "custom/device-notifier": {
      format: "{}",
      "return-type": "json",
      signal: sig("device_notifier"),
      interval: iv("device_notifier"),
      exec: ($scripts + "/services/devices/device-notifier-status.sh"),
      "on-click": ($s[0].device_notifier.on_click // ($scripts + "/services/devices/device-notifier.py --menu")),
      "on-click-right": ($s[0].device_notifier.on_click_right // ($scripts + "/services/devices/device-notifier-status.sh --refresh && " + $scripts + "/lib/waybar-signal.sh " + ((sig("device_notifier") // 19) | tostring)))
    },
    "custom/colorpicker": {
      format: "󰏘",
      tooltip: "Color Picker · Click to grab color",
      "on-click": ($s[0].colorpicker.on_click // ($scripts + "/capture/color-picker.sh"))
    },
    "custom/rgb": {
      format: "{}",
      "return-type": "json",
      tooltip: true,
      signal: sig("rgb"),
      interval: iv("rgb"),
      exec: ($scripts + "/system/rgb-status.sh"),
      "on-click": ($scripts + "/tools/app-open-key.sh openrgb"),
      "on-click-right": ($scripts + "/tools/app-open-key.sh ckb_next"),
      "on-click-middle": ($scripts + "/system/rgb-status.sh --refresh")
    },
    "custom/vaults": {
      format: "{}",
      "return-type": "json",
      signal: sig("vaults"),
      interval: iv("vaults"),
      exec: ($scripts + "/services/security/vaults-status.sh"),
      "on-click": ($s[0].vaults.on_click // ($scripts + "/services/security/vaults.py --menu")),
      "on-click-right": ($s[0].vaults.on_click_right // ($scripts + "/services/security/vaults-status.sh --refresh && " + $scripts + "/lib/waybar-signal.sh " + ((sig("vaults") // 21) | tostring)))
    },
    "custom/touchpad": {
      format: "{}",
      "return-type": "json",
      signal: sig("touchpad"),
      interval: iv("touchpad"),
      exec: ($scripts + "/lib/compositor-gate.sh --show hyprland -- " + $scripts + "/system/touchpad-status.sh"),
      "on-click": ($s[0].touchpad.on_click // ($scripts + "/system/touchpad.py --toggle")),
      "on-click-right": ($s[0].touchpad.on_click_right // ($scripts + "/system/touchpad-status.sh --refresh && " + $scripts + "/lib/waybar-signal.sh " + ((sig("touchpad") // 20) | tostring)))
    },
    "custom/weather": {
      format: "{}",
      "return-type": "json",
      interval: iv("weather"),
      exec: ($scripts + "/services/apps/weather-status.sh"),
      "on-click": ($s[0].weather.on_click // (app_open + " xdg-open https://wttr.in/")),
      "on-click-right": ($s[0].weather.on_click_right // (app_open + " xdg-open https://weather.com/")),
      "on-click-middle": ($s[0].weather.on_click_middle // ($scripts + "/services/apps/weather-status.sh --refresh"))
    },
    "custom/systemd": {
      format: "{}",
      "return-type": "json",
      interval: iv("systemd"),
      exec: ($scripts + "/system/systemd-status.sh"),
      "on-click": (app_open + " " + (app("systemd_failed") // "ghostty -e bash -c \"echo \\\"Failed System Services:\\\"; systemctl --failed; echo \\\"\\\"; echo \\\"Failed User Services:\\\"; systemctl --user --failed; echo \\\"\\\"; read -p \\\"Press Enter to close... \\\"\""))
    },
    "custom/github": {
      format: "{}",
      "return-type": "json",
      interval: iv("github"),
      exec: ($scripts + "/services/apps/github-status.sh"),
      "on-click": ((($s[0].github // {}).on_click) // (app_open + " xdg-open " + (app("github_notifications") // "https://github.com/notifications"))),
      "on-click-right": ((($s[0].github // {}).on_click_right) // (app_open + " xdg-open " + (app("github_home") // "https://github.com"))),
      "on-click-middle": ((($s[0].github // {}).on_click_middle) // ($scripts + "/services/apps/github-status.sh --refresh"))
    },
    "custom/device-battery": {
      format: "{}",
      "return-type": "json",
      signal: sig("device_battery"),
      interval: iv("device_battery"),
      exec: ($scripts + "/services/devices/device-battery-status.sh"),
      "on-click": (app_open + " " + (app("solaar") // "solaar")),
      "on-click-right": ($scripts + "/tools/app-open-key.sh input_settings"),
      "on-click-middle": ($scripts + "/services/devices/device-battery-status.sh --refresh")
    },
    "custom/streamdeck": {
      format: "{}",
      "return-type": "json",
      signal: sig("streamdeck"),
      interval: iv("streamdeck"),
      tooltip: true,
      exec: ($scripts + "/services/devices/streamdeck-status.sh"),
      "on-click": ((($s[0].streamdeck // {}).on_click) // (app_open + " streamdeck")),
      "on-click-right": ((($s[0].streamdeck // {}).on_click_right) // (app_open + " systemctl --user restart " + ((($s[0].streamdeck // {}).service_name) // "app-streamdeck-ui@autostart.service"))),
      "on-click-middle": ((($s[0].streamdeck // {}).on_click_middle) // ($scripts + "/services/devices/streamdeck-status.sh --refresh"))
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/utilities.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);
  def app($k): ($s[0].apps[$k] // "");
  def app_open: ($scripts + "/tools/app-open.sh");

  {
    mpris: {
      format: "{player_icon} {title}",
      "format-paused": "{status_icon} <i>{title}</i>",
      "player-icons": {
        default: "󰐊",
        mpv: "󰐊",
        chromium: "󰊯",
        firefox: "󰈹",
        vesktop: "󰙯"
      },
      "status-icons": {
        paused: "󰏤"
      },
      "max-length": ($s[0].audio.mpris_max_length // 32)
    },
    "custom/mpris": {
      format: "{}",
      exec: ($scripts + "/media/mpris-scroll.sh"),
      "on-click": "playerctl play-pause",
      "on-click-right": "playerctl next",
      "on-click-middle": "playerctl previous"
    },
    "custom/media-prev": {
      format: "{}",
      "return-type": "json",
      interval: "once",
      exec: ($scripts + "/media/media-prev.sh"),
      "on-click": "playerctl previous",
      "on-click-right": ("playerctl position " + (((($s[0].audio // {}).seek_back_sec) // 30) | tostring) + "-")
    },
    "custom/media-next": {
      format: "{}",
      "return-type": "json",
      interval: "once",
      exec: ($scripts + "/media/media-next.sh"),
      "on-click": "playerctl next",
      "on-click-right": ("playerctl position " + (((($s[0].audio // {}).seek_forward_sec) // 10) | tostring) + "+")
    },
    pulseaudio: {
      format: "{icon} {volume:3}%",
      "format-muted": "󰝟 {volume:3}%",
      "tooltip-format": "{desc}\nVolume: {volume}%\nLeft: open GoXLR · Right: audio menu · Middle: mute",
      "format-icons": {
        headphone: "󰋋",
        "hands-free": "󰋎",
        headset: "󰋎",
        phone: "󰄜",
        portable: "󰄝",
        car: "󰄋",
        default: ["󰕿", "󰖀", "󰕾"]
      },
      "on-click": ($s[0].audio.on_click // (app_open + " " + app("audio_mixer"))),
      "on-click-right": ($s[0].audio.on_click_right // ($scripts + "/media/audio-click.sh select")),
      "on-click-middle": ($s[0].audio.pulseaudio_mute_cmd // "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
      "on-scroll-up": ("wpctl set-volume -l " + (($s[0].audio.max_volume // 1.5) | tostring) + " @DEFAULT_AUDIO_SINK@ " + (($s[0].audio.volume_step // 5) | tostring) + "%+"),
      "on-scroll-down": ("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + (($s[0].audio.volume_step // 5) | tostring) + "%-")
    },
    "custom/mic": {
      format: "{}",
      "return-type": "json",
      signal: sig("mic"),
      interval: iv("mic"),
      exec: ($scripts + "/media/mic-status.sh"),
      "on-click": (app_open + " " + app("audio_mixer")),
      "on-click-right": ($scripts + "/media/audio-click.sh manage"),
      "on-click-middle": ($scripts + "/media/mic-toggle.sh")
    },
    bluetooth: {
      format: "󰂯",
      "format-disabled": "󰂲",
      "format-connected": "󰂱",
      "format-connected-battery": "󰂱",
      "tooltip-format": "{status}\n{controller_alias}: {controller_address}",
      "tooltip-format-connected": "{device_alias}\n{controller_alias}: {num_connections} connected",
      "tooltip-format-connected-battery": "{device_alias} {device_battery_percentage}%\n{controller_alias}: {num_connections} connected",
      "on-click": ($s[0].bluetooth.on_click // ($scripts + "/network/bluetooth-click.sh list")),
      "on-click-right": ($s[0].bluetooth.on_click_right // ($scripts + "/network/bluetooth-click.sh manage")),
      "on-click-middle": ($s[0].bluetooth.on_click_middle // ($scripts + "/network/bluetooth-click.sh toggle"))
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/audio.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" \
  --arg hour_format "$hour_format" \
  --arg date_format "$date_format" \
  --argjson first_day "$first_day" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def calfmt: ($s[0].clocks.calendar.format // {});

  def default_bottom_format:
    if $hour_format == "12" then
      if $date_format == "month-first" then "{:%a, %b %d %I:%M %p}" else "{:%a, %d %b %I:%M %p}" end
    else
      if $date_format == "month-first" then "{:%a, %b %d %H:%M}" else "{:%a, %d %b %H:%M}" end
    end;

  def default_bottom_tooltip:
    "<big>{:%Y-%m-%d}</big>\n<tt>{calendar}</tt>";

  {
    "clock#bottom": (
      {
        interval: iv("clock"),
        format: (($s[0].clocks.bottom.format | select(. != null and . != "" and . != "auto" and . != "null")) // default_bottom_format),
        "tooltip-format": (($s[0].clocks.bottom.tooltip_format | select(. != null and . != "" and . != "auto" and . != "null")) // default_bottom_tooltip),
        "on-click": ($scripts + "/tools/calendar-popup.sh"),
        "on-click-right": ($scripts + "/tools/app-open.sh " + ($s[0].apps.clock // "kclock")),
        calendar: {
          mode: ($s[0].clocks.calendar.mode // "month"),
          "on-scroll": ($s[0].clocks.calendar.on_scroll // 1),
          "first_day": (($s[0].clocks.calendar.first_day | select(. != null and . != "" and . != "auto" and . != "null")) // $first_day),
          format: calfmt
        },
        actions: {
          "on-scroll-up": "shift_down",
          "on-scroll-down": "shift_up"
        }
      }
      + (if ($s[0].clocks.locale != null and $s[0].clocks.locale != "" and $s[0].clocks.locale != "auto" and $s[0].clocks.locale != "null") then { locale: $s[0].clocks.locale } else {} end)
    )
  }
' | jq '.' >"$mod_dir/clock.generated.jsonc"

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

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);
  def app_open: ($scripts + "/tools/app-open.sh");

  {
    "custom/vpnstatus": {
      format: "{}",
      "return-type": "json",
      interval: iv("vpn"),
      signal: sig("vpn"),
      exec: ($scripts + "/network/vpn-status.sh"),
      "on-click": ("python3 " + $scripts + "/network/vpn-status-popup.py")
    },
    "custom/tailscale": {
      format: "{}",
      "return-type": "json",
      interval: iv("tailscale"),
      signal: sig("tailscale"),
      exec: ($scripts + "/network/tailscale-status.sh"),
      "on-click": (app_open + " " + ($s[0].network.tailscale_status_cmd // "ghostty -e tailscale status")),
      "on-click-right": (app_open + " xdg-open " + ($s[0].network.tailscale_admin_url // "http://100.100.100.100/"))
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

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);

  def privacy($kind):
    {
      key: ("custom/privacy-" + $kind),
      value: {
        format: "{}",
        "return-type": "json",
        interval: iv("privacy"),
        signal: sig("privacy"),
        exec: ($scripts + "/services/security/privacy-status.sh " + $kind),
        "on-click": ($scripts + "/services/security/privacy-click.sh " + $kind + " click"),
        "on-click-middle": ($scripts + "/services/security/privacy-click.sh " + $kind + " middle"),
        "on-click-right": ($scripts + "/services/security/privacy-click.sh " + $kind + " right"),
        tooltip: true
      }
    };

  ["screenshare", "webcam", "audio-in", "audio-out", "location"]
  | map(privacy(.))
  | from_entries
  | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/privacy.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);

  {
    "custom/active-window": {
      format: "{}",
      "return-type": "json",
      escape: true,
      exec: ($scripts + "/workspaces/active-window-scroll.sh"),
      tooltip: true,
      "on-click": ($scripts + "/workspaces/window-switcher.sh")
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/compositor.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);

  {
    "custom/keyboard-layout": {
      format: "{}",
      "return-type": "json",
      signal: sig("keyboard_layout"),
      interval: iv("keyboard_layout"),
      exec: ($scripts + "/system/keyboard-layout-status.sh"),
      "on-click": ($s[0].keyboard.on_click // ($scripts + "/system/keyboard-layout-click.sh next")),
      "on-click-right": ($s[0].keyboard.on_click_right // ($scripts + "/system/keyboard-layout-click.sh prev")),
      "on-click-middle": $s[0].keyboard.on_click_middle,
      "on-scroll-up": ($s[0].keyboard.on_scroll_up // ($scripts + "/system/keyboard-layout-click.sh prev")),
      "on-scroll-down": ($s[0].keyboard.on_scroll_down // ($scripts + "/system/keyboard-layout-click.sh next")),
      tooltip: true
    },
    "custom/gamemode": {
      format: "{}",
      "return-type": "json",
      signal: sig("gamemode"),
      interval: iv("gamemode"),
      exec: ($scripts + "/system/gamemode-status.sh"),
      "on-click": ($s[0].gamemode.on_click // ($scripts + "/system/gamemode-click.sh toggle")),
      "on-click-right": ($s[0].gamemode.on_click_right // ($scripts + "/system/gamemode-click.sh restore")),
      "on-click-middle": $s[0].gamemode.on_click_middle,
      tooltip: true
    },
    "custom/keybindhint": {
      format: "{}",
      "return-type": "json",
      interval: "once",
      exec: ($scripts + "/workspaces/keybindhint-status.sh"),
      "on-click": ($scripts + "/workspaces/keybindhint-click.sh"),
      tooltip: true
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/center-extras.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);

  {
    "custom/dock-windows": {
      format: "{}",
      "return-type": "json",
      "min-length": ($s[0].dock_windows.min_length // 64),
      "max-length": ($s[0].dock_windows.max_length // 160),
      expand: (if $s[0].dock_windows.expand != null then $s[0].dock_windows.expand else true end),
      align: ($s[0].dock_windows.align // 0.5),
      signal: sig("dock_windows"),
      interval: iv("dock_windows"),
      exec: ($scripts + "/dock/dock-windows-status.sh"),
      "on-click": ($scripts + "/dock/dock-windows-click.sh activate"),
      "on-click-right": ($scripts + "/dock/dock-windows-click.sh close-focused"),
      "on-click-middle": ($scripts + "/dock/dock-windows-click.sh cycle"),
      tooltip: true
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/dock-windows.generated.jsonc"

jq -n --slurpfile s "$settings" '
  {
    tray: {
      "icon-size": ($s[0].tray.icon_size // 16),
      spacing: ($s[0].tray.spacing // 10)
    }
  }
' | jq '.' >"$mod_dir/tray.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 0);

  {
    "custom/hyprnotify": {
      format: "{}",
      "return-type": "json",
      interval: iv("hypr_tools"),
      exec: ($scripts + "/services/hypr/hypr-bar-module-status.sh notify"),
      tooltip: false,
      "on-click": ($s[0].hypr_tools.hyprnotify_click // "hyprnotify show")
    },
    "custom/hyprlight": {
      format: "{}",
      "return-type": "json",
      interval: iv("hypr_tools"),
      exec: ($scripts + "/services/hypr/hypr-bar-module-status.sh light"),
      tooltip: false,
      "on-click": ($s[0].hypr_tools.hyprlight_click // "hyprlight osd")
    },
    "custom/hyprwhspr": {
      format: "{}",
      exec: ("sh " + $scripts + "/services/hypr/hyprwhspr-status-wrapper.sh"),
      interval: iv("hyprwhspr"),
      "return-type": "json",
      "exec-on-event": false,
      "on-click": ($s[0].hypr_tools.hyprwhspr_record // "/usr/lib/hyprwhspr/config/hyprland/hyprwhspr-tray.sh record"),
      "on-click-right": ($s[0].hypr_tools.hyprwhspr_restart // "/usr/lib/hyprwhspr/config/hyprland/hyprwhspr-tray.sh restart"),
      tooltip: true
    }
  }
' | jq '.' >"$mod_dir/hypr-tools.generated.jsonc"

jq -n --slurpfile s "$settings" '
  ($s[0].theme // {}) as $t
  | ($t.colors // {}) as $c
  | ($t.font_family // "JetBrainsMono Nerd Font") as $font
  | ($t.font_size // 13) as $size
  | ($t.tooltip_font_size // 12) as $tsize
  | ($t.border_radius // 8) as $radius
  | ($t.tooltip_padding // "8px 10px") as $tpad
  | "/* Generated from data/waybar-settings.json theme — do not edit by hand */\n\n"
    + "* {\n"
    + "    font-family: \"" + $font + "\", monospace;\n"
    + "    font-size: " + ($size | tostring) + "px;\n"
    + "    min-height: 0;\n"
    + "}\n\n"
    + "window#waybar {\n"
    + "    background: " + ($c.background // "rgba(6, 7, 14, 0.92)") + ";\n"
    + "    border-bottom: 1px solid " + ($c.border // "rgba(0, 229, 255, 0.25)") + ";\n"
    + "    color: " + ($c.foreground // "#c8f6ff") + ";\n"
    + "}\n\n"
    + "window#waybar.bottom {\n"
    + "    border-bottom: none;\n"
    + "    border-top: 1px solid " + ($c.border // "rgba(0, 229, 255, 0.25)") + ";\n"
    + "}\n\n"
    + "tooltip, #tooltip {\n"
    + "    background: " + ($c.tooltip_background // "#06070e") + ";\n"
    + "    border: 1px solid " + ($c.tooltip_border // "#005c66") + ";\n"
    + "    border-radius: " + ($radius | tostring) + "px;\n"
    + "}\n\n"
    + "tooltip label, #tooltip label {\n"
    + "    color: " + ($c.foreground // "#c8f6ff") + ";\n"
    + "    background: transparent;\n"
    + "    padding: " + $tpad + ";\n"
    + "    font-family: \"" + $font + "\", monospace;\n"
    + "    font-size: " + ($tsize | tostring) + "px;\n"
    + "}\n"
' -r >"$theme_dir/tokens.generated.css"
