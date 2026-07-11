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
