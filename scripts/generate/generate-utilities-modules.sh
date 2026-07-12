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
  def app($k): ($s[0].apps[$k] // "");
  def app_open: ($scripts + "/tools/app-open.sh");
  def brightness_out:
    ((($s[0].brightness // {}).per_output) as $p | if $p == false then false else true end)
    | if . then " \"$WAYBAR_OUTPUT_NAME\"" else "" end;
  def capture_out:
    ((($s[0].capture // {}).per_output) as $p | if $p == false then false else true end)
    | if . then " \"$WAYBAR_OUTPUT_NAME\"" else "" end;

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
      "on-click": ($scripts + "/capture/screenshot-click.sh select" + capture_out),
      "on-click-right": ($scripts + "/capture/screenshot-click.sh full" + capture_out),
      "on-click-middle": ($scripts + "/capture/screenshot-click.sh window" + capture_out)
    },
    "custom/screenrecord": {
      format: "{}",
      "return-type": "json",
      signal: sig("screenrecord"),
      interval: iv("screenrecord"),
      exec: ($scripts + "/capture/screenrecord-status.sh"),
      "on-click": ($scripts + "/capture/screenrecord-click.sh select" + capture_out),
      "on-click-right": ($scripts + "/capture/screenrecord-click.sh full" + capture_out),
      "on-click-middle": ($scripts + "/capture/screenrecord-click.sh window" + capture_out)
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
        + brightness_out
      ),
      "on-click": ($scripts + "/system/brightness-control.sh adjust -" + (($s[0].brightness.step_down // 5) | tostring) + brightness_out),
      "on-click-right": ($scripts + "/system/brightness-control.sh adjust +" + (($s[0].brightness.step_up // 5) | tostring) + brightness_out),
      "on-click-middle": ($scripts + "/system/brightness-control.sh set " + (($s[0].brightness.middle_set // 80) | tostring) + brightness_out),
      "on-scroll-up": ($scripts + "/system/brightness-control.sh adjust +" + (($s[0].brightness.step_up // 5) | tostring) + brightness_out),
      "on-scroll-down": ($scripts + "/system/brightness-control.sh adjust -" + (($s[0].brightness.step_down // 5) | tostring) + brightness_out)
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
    "custom/power-menu": {
      format: "󰐦",
      tooltip: "Power menu (rofi grid)\nLock · Logout · Suspend · Reboot · Shutdown",
      "on-click": ($scripts + "/system/power-click.sh menu")
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
      "on-click": ($s[0].weather.on_click // (app_open + " xdg-open https://open-meteo.com/")),
      "on-click-right": ($s[0].weather.on_click_right // (app_open + " xdg-open https://weather.com/")),
      "on-click-middle": ($s[0].weather.on_click_middle // ($scripts + "/services/apps/weather-status.sh --refresh"))
    },
    "custom/pomodoro": {
      format: "{}",
      "return-type": "json",
      signal: sig("pomodoro"),
      interval: iv("pomodoro"),
      exec: ($scripts + "/tools/pomodoro-status.sh"),
      "on-click": ($scripts + "/tools/pomodoro-click.sh toggle"),
      "on-click-right": ($scripts + "/tools/pomodoro-click.sh reset"),
      "on-click-middle": ($scripts + "/tools/pomodoro-click.sh skip")
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
      "on-click": ((($s[0].streamdeck // {}).on_click) // ($scripts + "/services/devices/streamdeck-click.sh open")),
      "on-click-right": ((($s[0].streamdeck // {}).on_click_right) // ($scripts + "/services/devices/streamdeck-click.sh restart")),
      "on-click-middle": ((($s[0].streamdeck // {}).on_click_middle) // ($scripts + "/services/devices/streamdeck-click.sh refresh"))
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/utilities.generated.jsonc"
