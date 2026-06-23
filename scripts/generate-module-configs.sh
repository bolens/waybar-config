#!/usr/bin/env bash
# Regenerate module JSONC files from data/waybar-settings.json.
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
. "${0%/*}/waybar-settings.sh"
. "${0%/*}/waybar-cache-helpers.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
scripts='$WAYBAR_HOME/scripts'

hour_format=$(detect_clock_format)
date_format=$(detect_date_format)
first_day=$(detect_first_weekday)

[ -f "$settings" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

mod_dir="$WAYBAR_HOME/modules"
theme_dir="$WAYBAR_HOME/theme"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // empty);
  def app($k): ($s[0].apps[$k] // "");
  def app_open: ($scripts + "/app-open.sh");

  {
    "custom/notifications": {
      format: "{0}{icon}",
      "return-type": "json",
      signal: sig("notifications"),
      interval: iv("notifications"),
      escape: true,
      exec: ($scripts + "/notifications-status.sh"),
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
      "on-click": ($scripts + "/notifications-click.sh open"),
      "on-click-right": ($scripts + "/notifications-click.sh dnd"),
      "on-click-middle": ($scripts + "/notifications-click.sh settings")
    },
    "custom/screenshot": {
      format: "{}",
      "return-type": "json",
      interval: iv("screenshot"),
      exec: ($scripts + "/screenshot-status.sh"),
      "on-click": ($scripts + "/screenshot-click.sh select"),
      "on-click-right": ($scripts + "/screenshot-click.sh full"),
      "on-click-middle": ($scripts + "/screenshot-click.sh window")
    },
    "custom/screenrecord": {
      format: "{}",
      "return-type": "json",
      signal: sig("screenrecord"),
      interval: iv("screenrecord"),
      exec: ($scripts + "/screenrecord-status.sh"),
      "on-click": ($scripts + "/screenrecord-click.sh select"),
      "on-click-right": ($scripts + "/screenrecord-click.sh full"),
      "on-click-middle": ($scripts + "/screenrecord-click.sh window")
    },
    "custom/nightlight": {
      format: "{}",
      "return-type": "json",
      signal: sig("nightlight"),
      interval: iv("nightlight"),
      exec: ($scripts + "/nightlight-status.sh"),
      "on-click": ($scripts + "/nightlight-toggle.sh toggle"),
      "on-click-middle": ($scripts + "/nightlight-toggle.sh force_toggle"),
      "on-click-right": ($scripts + "/nightlight-toggle.sh settings")
    },
    "custom/clipboard": {
      format: "{0}{icon}",
      "return-type": "json",
      signal: sig("clipboard"),
      interval: iv("clipboard"),
      escape: true,
      exec: ($scripts + "/clipboard-status.sh"),
      "format-icons": {
        normal: "󰅌",
        empty: "󰅍",
        disabled: "󰅌",
        unknown: "󰅌"
      },
      "on-click": ($scripts + "/clipboard-click.sh open"),
      "on-click-right": ($scripts + "/clipboard-click.sh clear"),
      "on-click-middle": ($scripts + "/clipboard-click.sh edit")
    },
    "custom/brightness": {
      format: "{}",
      "return-type": "json",
      signal: sig("brightness"),
      interval: iv("brightness"),
      exec: (
        $scripts + "/compositor-gate.sh --hide "
        + ($s[0].brightness.hide_on_compositor // "hyprland")
        + " -- " + $scripts + "/brightness-status.sh"
      ),
      "on-click": ($scripts + "/brightness-control.sh adjust -" + (($s[0].brightness.step_down // 5) | tostring)),
      "on-click-right": ($scripts + "/brightness-control.sh adjust +" + (($s[0].brightness.step_up // 5) | tostring)),
      "on-click-middle": ($scripts + "/brightness-control.sh set " + (($s[0].brightness.middle_set // 80) | tostring)),
      "on-scroll-up": ($scripts + "/brightness-control.sh adjust +" + (($s[0].brightness.step_up // 5) | tostring)),
      "on-scroll-down": ($scripts + "/brightness-control.sh adjust -" + (($s[0].brightness.step_down // 5) | tostring))
    },
    "custom/powerprofiles": {
      format: "{}",
      "return-type": "json",
      signal: sig("powerprofiles"),
      interval: iv("powerprofiles"),
      exec: ($scripts + "/powerprofiles-status.sh"),
      "on-click": ($scripts + "/powerprofiles-click.sh menu"),
      "on-click-right": ($scripts + "/powerprofiles-click.sh power-saver"),
      "on-click-middle": ($scripts + "/powerprofiles-click.sh balanced"),
      "on-scroll-up": ($scripts + "/powerprofiles-click.sh next"),
      "on-scroll-down": ($scripts + "/powerprofiles-click.sh next")
    },
    "custom/discord": {
      format: "{}",
      "return-type": "json",
      interval: iv("discord"),
      exec: ($scripts + "/discord-status.sh"),
      "on-click": (app_open + " " + app("discord")),
      "on-click-right": ($scripts + "/discord-click.sh mute"),
      "on-click-middle": ($scripts + "/discord-click.sh deafen")
    },
    "custom/lock": {
      format: "",
      "tooltip-format": "Lock screen",
      "on-click": ($scripts + "/power-click.sh lock")
    },
    "custom/logout": {
      format: "󰍃",
      "tooltip-format": "Logout session",
      "on-click": ($scripts + "/power-click.sh logout")
    },
    "custom/suspend": {
      format: "󰤄",
      "tooltip-format": "Suspend system",
      "on-click": ($scripts + "/power-click.sh suspend")
    },
    "custom/reboot": {
      format: "󰜉",
      "tooltip-format": "Reboot system",
      "on-click": ($scripts + "/power-click.sh reboot")
    },
    "custom/shutdown": {
      format: "󰐥",
      "tooltip-format": "Shutdown system",
      "on-click": ($scripts + "/power-click.sh shutdown")
    },
    "custom/kdeconnect": {
      format: "{}",
      "return-type": "json",
      signal: sig("kdeconnect"),
      interval: iv("kdeconnect"),
      exec: ($scripts + "/kdeconnect-status.sh"),
      "on-click": ($scripts + "/kdeconnect-status.sh --ring")
    },
    "custom/weather": {
      format: "{}",
      "return-type": "json",
      interval: iv("weather"),
      exec: ($scripts + "/weather-status.sh"),
      "on-click": (app_open + " xdg-open https://wttr.in/")
    },
    "custom/systemd": {
      format: "{}",
      "return-type": "json",
      interval: iv("systemd"),
      exec: ($scripts + "/systemd-status.sh"),
      "on-click": (app_open + " ghostty -e bash -c \"echo \\\"Failed System Services:\\\"; systemctl --failed; echo \\\"\\\"; echo \\\"Failed User Services:\\\"; systemctl --user --failed; echo \\\"\\\"; read -p \\\"Press Enter to close... \\\"\"")
    },
    "custom/github": {
      format: "{}",
      "return-type": "json",
      interval: iv("github"),
      exec: ($scripts + "/github-status.sh"),
      "on-click": (app_open + " xdg-open https://github.com/notifications")
    },
    "custom/device-battery": {
      format: "{}",
      "return-type": "json",
      signal: sig("device_battery"),
      interval: iv("device_battery"),
      exec: ($scripts + "/device-battery-status.sh"),
      "on-click": (app_open + " solaar"),
      "on-click-right": (app_open + " systemsettings"),
      "on-click-middle": ($scripts + "/device-battery-status.sh --refresh")
    }
  }
' | jq '.' >"$mod_dir/utilities.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // empty);
  def app($k): ($s[0].apps[$k] // "");
  def app_open: ($scripts + "/app-open.sh");

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
      exec: ($scripts + "/mpris-scroll.sh"),
      "on-click": "playerctl play-pause",
      "on-click-right": "playerctl next",
      "on-click-middle": "playerctl previous"
    },
    "custom/media-prev": {
      format: "{}",
      "return-type": "json",
      interval: 2,
      exec: ($scripts + "/media-prev.sh"),
      "on-click": "playerctl previous",
      "on-click-right": "playerctl position 30-"
    },
    "custom/media-next": {
      format: "{}",
      "return-type": "json",
      interval: 2,
      exec: ($scripts + "/media-next.sh"),
      "on-click": "playerctl next",
      "on-click-right": "playerctl position 10+"
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
      "on-click": (app_open + " " + app("audio_mixer")),
      "on-click-right": ($scripts + "/audio-click.sh select"),
      "on-click-middle": ($s[0].audio.pulseaudio_mute_cmd // "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
      "on-scroll-up": "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+",
      "on-scroll-down": "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    },
    "custom/mic": {
      format: "{}",
      "return-type": "json",
      signal: sig("mic"),
      interval: iv("mic"),
      exec: ($scripts + "/mic-status.sh"),
      "on-click": (app_open + " " + app("audio_mixer")),
      "on-click-right": ($scripts + "/audio-click.sh manage"),
      "on-click-middle": ($scripts + "/mic-toggle.sh")
    },
    bluetooth: {
      format: "󰂯",
      "format-disabled": "󰂲",
      "format-connected": "󰂱",
      "format-connected-battery": "󰂱",
      "tooltip-format": "{status}\n{controller_alias}: {controller_address}",
      "tooltip-format-connected": "{device_alias}\n{controller_alias}: {num_connections} connected",
      "tooltip-format-connected-battery": "{device_alias} {device_battery_percentage}%\n{controller_alias}: {num_connections} connected",
      "on-click": ($scripts + "/bluetooth-click.sh list"),
      "on-click-right": ($scripts + "/bluetooth-click.sh manage"),
      "on-click-middle": ($scripts + "/bluetooth-click.sh toggle")
    }
  }
' | jq '.' >"$mod_dir/audio.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" \
  --arg hour_format "$hour_format" \
  --arg date_format "$date_format" \
  --argjson first_day "$first_day" '
  def iv($k): ($s[0].poll_intervals[$k] // 1);
  def calfmt: ($s[0].clocks.calendar.format // {});

  def default_top_format:
    if $hour_format == "12" then
      if $date_format == "month-first" then "{:%I:%M %p  %a, %b %d}" else "{:%I:%M %p  %a, %d %b}" end
    else
      if $date_format == "month-first" then "{:%H:%M  %a, %b %d}" else "{:%H:%M  %a, %d %b}" end
    end;

  def default_bottom_format:
    if $hour_format == "12" then
      if $date_format == "month-first" then "{:%a, %b %d %I:%M %p}" else "{:%a, %d %b %I:%M %p}" end
    else
      if $date_format == "month-first" then "{:%a, %b %d %H:%M}" else "{:%a, %d %b %H:%M}" end
    end;

  def default_top_tooltip:
    if $date_format == "month-first" then
      "<big>{:%A, %B %d, %Y}</big>\n<tt>{calendar}</tt>"
    else
      "<big>{:%A, %d %B %Y}</big>\n<tt>{calendar}</tt>"
    end;

  def default_bottom_tooltip:
    "<big>{:%Y-%m-%d}</big>\n<tt>{calendar}</tt>";

  {
    "clock#top": {
      interval: iv("clock"),
      format: (($s[0].clocks.top.format | select(. != null and . != "" and . != "auto" and . != "null")) // default_top_format),
      "tooltip-format": (($s[0].clocks.top.tooltip_format | select(. != null and . != "" and . != "auto" and . != "null")) // default_top_tooltip),
      "on-click": ($scripts + "/calendar-popup.sh"),
      "on-click-right": ($scripts + "/app-open.sh " + ($s[0].apps.clock // "kclock")),
      calendar: {
        mode: ($s[0].clocks.calendar.mode // "month"),
        "on-scroll": ($s[0].clocks.calendar.on_scroll // 1),
        "first_day": ($s[0].clocks.calendar.first_day // $first_day),
        format: calfmt
      },
      actions: {
        "on-scroll-up": "shift_down",
        "on-scroll-down": "shift_up"
      }
    },
    "clock#bottom": {
      interval: iv("clock"),
      format: (($s[0].clocks.bottom.format | select(. != null and . != "" and . != "auto" and . != "null")) // default_bottom_format),
      "tooltip-format": (($s[0].clocks.bottom.tooltip_format | select(. != null and . != "" and . != "auto" and . != "null")) // default_bottom_tooltip),
      "on-click": ($scripts + "/calendar-popup.sh"),
      "on-click-right": ($scripts + "/app-open.sh " + ($s[0].apps.clock // "kclock")),
      calendar: {
        mode: ($s[0].clocks.calendar.mode // "month"),
        "on-scroll": ($s[0].clocks.calendar.on_scroll // 1),
        "first_day": ($s[0].clocks.calendar.first_day // $first_day),
        format: calfmt
      },
      actions: {
        "on-scroll-up": "shift_down",
        "on-scroll-down": "shift_up"
      }
    }
  }
' | jq '.' >"$mod_dir/clock.generated.jsonc"

jq -n --slurpfile s "$settings" '
  def drawer($key; $module):
    {
      key: ("custom/" + $module),
      value: {
        format: ($s[0].drawers.icons[$key].format // ""),
        "tooltip-format": ($s[0].drawers.icons[$key].tooltip // "")
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
  def sig($k): ($s[0].signals[$k] // empty);
  def app_open: ($scripts + "/app-open.sh");

  {
    "custom/vpnstatus": {
      format: "{}",
      "return-type": "json",
      interval: iv("vpn"),
      signal: sig("vpn"),
      exec: ($scripts + "/vpn-status.sh"),
      "on-click": ("python3 " + $scripts + "/vpn-status-popup.py")
    },
    "custom/tailscale": {
      format: "{}",
      "return-type": "json",
      interval: iv("tailscale"),
      signal: sig("tailscale"),
      exec: ($scripts + "/tailscale-status.sh"),
      "on-click": (app_open + " " + ($s[0].network.tailscale_status_cmd // "ghostty -e tailscale status")),
      "on-click-right": (app_open + " xdg-open " + ($s[0].network.tailscale_admin_url // "http://100.100.100.100/"))
    }
  }
' | jq -c '.' >"$mod_dir/network-custom.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // empty);

  def privacy($kind):
    {
      key: ("custom/privacy-" + $kind),
      value: {
        format: "{}",
        "return-type": "json",
        interval: iv("privacy"),
        signal: sig("privacy"),
        exec: ($scripts + "/privacy-status.sh " + $kind),
        "on-click": ($scripts + "/privacy-click.sh " + $kind + " click"),
        "on-click-middle": ($scripts + "/privacy-click.sh " + $kind + " middle"),
        "on-click-right": ($scripts + "/privacy-click.sh " + $kind + " right"),
        tooltip: true
      }
    };

  ["screenshare", "webcam", "audio-in", "audio-out", "location"]
  | map(privacy(.))
  | from_entries
' | jq '.' >"$mod_dir/privacy.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // empty);

  {
    "custom/active-window": {
      format: "{}",
      "return-type": "json",
      escape: true,
      exec: ($scripts + "/active-window-scroll.sh"),
      tooltip: true,
      "on-click": ($scripts + "/window-switcher.sh")
    }
  }
' | jq '.' >"$mod_dir/compositor.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // empty);

  {
    "custom/keyboard-layout": {
      format: "{}",
      "return-type": "json",
      signal: sig("keyboard_layout"),
      interval: iv("keyboard_layout"),
      exec: ($scripts + "/keyboard-layout-status.sh"),
      tooltip: true
    },
    "custom/gamemode": {
      format: "{}",
      "return-type": "json",
      signal: sig("gamemode"),
      interval: iv("gamemode"),
      exec: ($scripts + "/gamemode-status.sh"),
      "on-click": ($scripts + "/gamemode-click.sh toggle"),
      "on-click-right": ($scripts + "/gamemode-click.sh restore"),
      tooltip: true
    },
    "custom/keybindhint": {
      format: "{}",
      "return-type": "json",
      interval: "once",
      exec: ($scripts + "/keybindhint-status.sh"),
      "on-click": ($scripts + "/keybindhint-click.sh"),
      tooltip: true
    }
  }
' | jq '.' >"$mod_dir/center-extras.generated.jsonc"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // empty);

  {
    "custom/dock-windows": {
      format: "{}",
      "return-type": "json",
      "min-length": ($s[0].dock_windows.min_length // 64),
      "max-length": ($s[0].dock_windows.max_length // 160),
      expand: ($s[0].dock_windows.expand // true),
      align: ($s[0].dock_windows.align // 0.5),
      signal: sig("dock_windows"),
      interval: iv("dock_windows"),
      exec: ($scripts + "/dock-windows-status.sh"),
      "on-click": ($scripts + "/dock-windows-click.sh activate"),
      "on-click-right": ($scripts + "/dock-windows-click.sh close-focused"),
      "on-click-middle": ($scripts + "/dock-windows-click.sh cycle")
    }
  }
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
  def iv($k): ($s[0].poll_intervals[$k] // 0);

  {
    "custom/hyprnotify": {
      format: "{}",
      "return-type": "json",
      interval: iv("hypr_tools"),
      exec: ($scripts + "/hypr-bar-module-status.sh notify"),
      tooltip: false,
      "on-click": ($s[0].hypr_tools.hyprnotify_click // "hyprnotify show")
    },
    "custom/hyprlight": {
      format: "{}",
      "return-type": "json",
      interval: iv("hypr_tools"),
      exec: ($scripts + "/hypr-bar-module-status.sh light"),
      tooltip: false,
      "on-click": ($s[0].hypr_tools.hyprlight_click // "hyprlight osd")
    },
    "custom/hyprwhspr": {
      format: "{}",
      exec: ("sh " + $scripts + "/hyprwhspr-status-wrapper.sh"),
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
    + "tooltip {\n"
    + "    background: " + ($c.background // "rgba(6, 7, 14, 0.96)") + ";\n"
    + "    border: 1px solid " + ($c.border // "rgba(0, 229, 255, 0.35)") + ";\n"
    + "    border-radius: " + ($radius | tostring) + "px;\n"
    + "    box-shadow: 0 0 14px rgba(0, 229, 255, 0.18);\n"
    + "}\n\n"
    + "tooltip label {\n"
    + "    color: " + ($c.foreground // "#c8f6ff") + ";\n"
    + "    background: transparent;\n"
    + "    padding: 8px 10px;\n"
    + "    font-family: \"" + $font + "\", monospace;\n"
    + "    font-size: " + ($tsize | tostring) + "px;\n"
    + "}\n"
' -r >"$theme_dir/tokens.generated.css"
