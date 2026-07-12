#!/usr/bin/env bash
# Calendar popup (yad/rofi) launched from the clock module.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

offset="${1:-0}"
case "$offset" in
  '' | *[!0-9-]*)
    offset=0
    ;;
esac

script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
# shellcheck source=rofi-popup-lib.sh
. "$WAYBAR_SCRIPTS/lib/rofi-popup-lib.sh"

first_day=$(detect_first_weekday)

if ! command -v rofi >/dev/null 2>&1; then
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Calendar" "rofi is not installed (needed for calendar popup)."
  fi
  exit 1
fi

month_date() {
  base="$(date +%Y-%m-15)"
  date -d "$base $1 month" "$2"
}

month_label() {
  month_date "$1" +"%B %Y"
}

centered_month_label() {
  center_text "$(month_label "$1")" 38
}

calendar_grid() {
  target_year="$(month_date "$1" +%Y)"
  target_month_num="$(month_date "$1" +%m)"
  today_year="$(date +%Y)"
  today_month="$(date +%m)"
  today_day="$(date +%d)"

  cal_opts=""
  if [ "${first_day:-0}" = "1" ]; then
    cal_opts="-m"
  elif [ "${first_day:-0}" = "0" ]; then
    cal_opts="-s"
  fi

  if command -v cal >/dev/null 2>&1; then
    cal $cal_opts "$target_month_num" "$target_year"
  else
    ncal -b $cal_opts "$target_month_num" "$target_year"
  fi | sed '1d;/^[[:space:]]*$/d' | while IFS= read -r line; do
    if [ "$target_year" = "$today_year" ] && [ "$target_month_num" = "$today_month" ]; then
      line="$(printf '%s' "$line" | sed -E "s/(^| )${today_day}([^0-9]|$)/\\1[${today_day}]\\2/")"
    fi
    center_text "$line" 38
    printf '\n'
  done
}

selected_row() {
  if [ "$1" != "0" ]; then
    printf '1\n'
    return
  fi

  row="$(calendar_grid 0 | awk '/\[[0-9][0-9]?\]/{print NR; exit}')"
  if [ -n "$row" ]; then
    printf '%s\n' "$((row + 1))"
  else
    printf '1\n'
  fi
}

cal_width=$(waybar_settings_get '.rofi.calendar.width' '420')
cal_xoff=$(waybar_settings_get '.rofi.calendar.x_offset' '-30')
cal_yoff=$(waybar_settings_get '.rofi.calendar.y_offset' '0')

theme_window="
  window {
    width: ${cal_width}px;
    location: northeast;
    anchor: northeast;
    x-offset: ${cal_xoff}px;
    y-offset: ${cal_yoff}px;
    border: 2px;
    border-color: #00e5ff;
    border-radius: 8px;
    background-color: #090b12f2;
  }
"

theme="${theme_window}"'
  mainbox {
    padding: 2px;
    background-color: transparent;
  }
  message {
    padding: 4px 10px 8px 10px;
    background-color: transparent;
    border: 0px;
    text-color: #ff9df4;
  }
  inputbar {
    enabled: false;
  }
  listview {
    lines: 9;
    columns: 1;
    spacing: 1px;
    scrollbar: false;
    dynamic: false;
    fixed-height: true;
    background-color: transparent;
    margin: 3px 0px 0px 0px;
  }
  element {
    padding: 4px 8px;
    border-radius: 4px;
    background-color: #0d111c;
    text-color: #d6f7ff;
  }
  element normal.normal {
    background-color: #0d111c;
    text-color: #d6f7ff;
  }
  element alternate.normal {
    background-color: #0a0e18;
    text-color: #d6f7ff;
  }
  element selected.normal {
    background-color: #1a1030;
    border: 1px;
    border-color: #ff4fd8;
    text-color: #ffffff;
  }
  element-text {
    font: "JetBrainsMono Nerd Font 12";
    background-color: transparent;
    text-color: inherit;
  }
'

while :; do
  prev_row="$(center_text "<  $(month_label "$((offset - 1))")" 38)"
  title_row="$(centered_month_label "$offset")"
  next_row="$(center_text ">  $(month_label "$((offset + 1))")" 38)"
  rows="$(printf '%s\n%s\n%s\n%s\n' "$prev_row" "$title_row" "$(calendar_grid "$offset")" "$next_row")"
  row_index="$(selected_row "$offset")"
  hint_l1="$(format_hints_row "[Alt+p/↑]      - Month" "+    [Alt+n/↓]" 38)"
  hint_l3="$(format_hints_row "[Alt+t] Today" "" 38)"
  hint_l2="$(format_hints_row "[Alt+P/←]      - Year" "+     [Alt+N/→]" 38)"
  sep='──────── Calendar Navigation ─────────'
  hints="$(printf "%s\n%s\n%s\n%s" \
    "<span foreground='#8aa2c5'>${hint_l1}</span>" \
    "<span foreground='#8aa2c5'>${hint_l2}</span>" \
    "<span foreground='#8aa2c5'>${hint_l3}</span>" \
    "<span foreground='#76819a'>${sep}</span>")"

  set +e
  choice="$(printf '%s\n' "$rows" | rofi -dmenu -i -no-custom -selected-row "$row_index" -kb-custom-1 "Alt+p,Alt+Up" -kb-custom-2 "Alt+n,Alt+Down" -kb-custom-3 "Alt+Left,Alt+Shift+P" -kb-custom-4 "Alt+Right,Alt+Shift+N" -kb-custom-5 "Alt+t" -theme-str "$theme" -mesg "$hints" -markup -p "$(month_label "$offset")")"
  status=$?
  set -e

  case "$status" in
    10)
      offset=$((offset - 1))
      continue
      ;;
    11)
      offset=$((offset + 1))
      continue
      ;;
    12)
      offset=$((offset - 12))
      continue
      ;;
    13)
      offset=$((offset + 12))
      continue
      ;;
    14)
      offset=0
      continue
      ;;
    0)
      if [ "$choice" = "$prev_row" ]; then
        offset=$((offset - 1))
        continue
      fi
      if [ "$choice" = "$title_row" ]; then
        continue
      fi
      if [ "$choice" = "$next_row" ]; then
        offset=$((offset + 1))
        continue
      fi
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac
done
