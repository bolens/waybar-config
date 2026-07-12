#!/usr/bin/env bash
# Domain module emitter (split from former generate-module-configs.sh).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
. "$WAYBAR_SCRIPTS/lib/theme-colors-lib.sh"
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
mkdir -p "$mod_dir" "$theme_dir"

# Resolve theme colors (preset merge when mode=preset) for calendar pango spans.
colors_json="$(waybar_theme_resolve_colors "$settings")"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" \
  --arg hour_format "$hour_format" \
  --arg date_format "$date_format" \
  --argjson first_day "$first_day" \
  --argjson theme_colors "$colors_json" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);

  # Calendar format is always rebuilt from colors (clocks.calendar.colors // theme).
  # Static format spans in settings are ignored so presets recolor the calendar.
  def cal_colors:
    ($s[0].clocks.calendar.colors // {}) as $cc
    | {
        months: ($cc.months // $theme_colors.critical // "#ff2a7f"),
        weekdays: ($cc.weekdays // $theme_colors.warning // "#ffe600"),
        days: ($cc.days // $theme_colors.foreground // "#c8f6ff"),
        today: ($cc.today // $theme_colors.accent // $theme_colors.workspace_visible // "#00e5ff")
      };

  def calfmt:
    cal_colors as $c
    | {
        months: ("<span color=\"" + $c.months + "\"><b>{}</b></span>"),
        weekdays: ("<span color=\"" + $c.weekdays + "\"><b>{}</b></span>"),
        days: ("<span color=\"" + $c.days + "\">{}</span>"),
        today: ("<span color=\"" + $c.today + "\"><b><u>{}</u></b></span>")
      };

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
