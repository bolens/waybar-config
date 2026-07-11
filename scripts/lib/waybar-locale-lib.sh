#!/usr/bin/env sh
# Locale / clock / weather format helpers for Waybar.
_get_config_override() {
  _path="$1"
  _default="$2"
  _val=""
  if command -v waybar_settings_get >/dev/null 2>&1; then
    _val=$(waybar_settings_get "$_path" "$_default")
  else
    _home="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
    _file="$_home/data/waybar-settings.json"
    if [ -f "$_file" ] && command -v jq >/dev/null 2>&1; then
      _val=$(jq -r --arg default "$_default" "$_path // \$default" "$_file" 2>/dev/null || printf '%s' "$_default")
    else
      _val="$_default"
    fi
  fi
  if [ "$_val" = "auto" ] || [ -z "$_val" ] || [ "$_val" = "null" ]; then
    printf '%s' "$_default"
  else
    printf '%s' "$_val"
  fi
}

detect_clock_format() {
  config_val=$(_get_config_override '.clocks.hour_format' 'auto')
  if [ "$config_val" != "auto" ]; then
    printf '%s\n' "$config_val"
    return
  fi
  if command -v locale >/dev/null 2>&1; then
    t_fmt=$(locale t_fmt 2>/dev/null || true)
    case "$t_fmt" in
      *%r* | *%I* | *%p*)
        printf '12\n'
        return
        ;;
    esac
  fi
  printf '24\n'
}

detect_date_format() {
  config_val=$(_get_config_override '.clocks.date_format' 'auto')
  if [ "$config_val" != "auto" ]; then
    printf '%s\n' "$config_val"
    return
  fi
  if command -v locale >/dev/null 2>&1; then
    d_fmt=$(locale d_fmt 2>/dev/null || true)
    case "$d_fmt" in
      *%d*%m* | *%d*%b* | *%d*%B* | *%e*%m* | *%e*%b* | *%e*%B*)
        printf 'day-first\n'
        return
        ;;
      *%m*%d* | *%b*%d* | *%B*%d* | *%m*%e* | *%b*%e* | *%B*%e*)
        printf 'month-first\n'
        return
        ;;
    esac
  fi
  printf 'day-first\n'
}

detect_weather_unit() {
  # CI / test pin (settings .json is overwritten from .jsonc on load).
  case "${WAYBAR_WEATHER_UNIT:-}" in
    [Cc])
      printf 'C\n'
      return
      ;;
    [Ff])
      printf 'F\n'
      return
      ;;
  esac
  config_val=$(_get_config_override '.weather.unit' 'auto')
  if [ "$config_val" != "auto" ]; then
    printf '%s\n' "$config_val"
    return
  fi
  if command -v locale >/dev/null 2>&1; then
    meas=$(locale measurement 2>/dev/null || true)
    if [ "$meas" = "1" ]; then
      printf 'C\n'
      return
    elif [ "$meas" = "2" ]; then
      printf 'F\n'
      return
    fi
  fi
  for var in "${LC_MEASUREMENT:-}" "${LANG:-}"; do
    case "$var" in
      *_US* | *_LR* | *_MM*)
        printf 'F\n'
        return
        ;;
    esac
  done
  printf 'C\n'
}

format_locale_datetime() {
  timestamp="$1"
  mode="${2:-long}"

  hr=$(detect_clock_format)
  dt=$(detect_date_format)

  time_fmt="%H:%M"
  [ "$hr" = "12" ] && time_fmt="%I:%M %p"

  if [ "$dt" = "day-first" ]; then
    date_long="%e %B %Y"
    date_short="%d/%m/%Y"
  else
    date_long="%B %e, %Y"
    date_short="%m/%d/%Y"
  fi

  case "$mode" in
    time-only)
      fmt="$time_fmt"
      ;;
    date-only | date-only-long)
      fmt="$date_long"
      ;;
    date-only-short)
      fmt="$date_short"
      ;;
    short)
      fmt="$date_short $time_fmt"
      ;;
    *)
      fmt="$date_long $time_fmt"
      ;;
  esac

  date -d "@$timestamp" "+$fmt" 2>/dev/null || date -r "$timestamp" "+$fmt" 2>/dev/null || printf "%s" "$timestamp"
}

format_locale_temp() {
  temp_c="$1"
  mode="${2:-both}"

  unit=$(detect_weather_unit)
  temp_f=$((temp_c * 9 / 5 + 32))

  if [ "$mode" = "short" ]; then
    if [ "$unit" = "F" ]; then
      printf '%s°F\n' "$temp_f"
    else
      printf '%s°C\n' "$temp_c"
    fi
  else
    if [ "$unit" = "F" ]; then
      printf '%s°F (%s°C)\n' "$temp_f" "$temp_c"
    else
      printf '%s°C (%s°F)\n' "$temp_c" "$temp_f"
    fi
  fi
}

detect_first_weekday() {
  config_val=$(_get_config_override '.clocks.calendar.first_day' 'auto')
  if [ "$config_val" != "auto" ]; then
    printf '%s\n' "$config_val"
    return
  fi
  if command -v locale >/dev/null 2>&1; then
    w1st=$(locale week-1stday 2>/dev/null || true)
    fwd=$(locale first_weekday 2>/dev/null || true)

    if [ -n "$w1st" ] && [ -n "$fwd" ]; then
      if [ "$w1st" = "19971130" ]; then
        if [ "$fwd" = "1" ]; then
          printf '0\n'
          return
        elif [ "$fwd" = "2" ]; then
          printf '1\n'
          return
        fi
      elif [ "$w1st" = "19971201" ]; then
        if [ "$fwd" = "1" ]; then
          printf '1\n'
          return
        fi
      fi
    fi
  fi

  for var in "${LC_TIME:-}" "${LANG:-}"; do
    case "$var" in
      *_US* | *_CA* | *_IL* | *_IN* | *_JM* | *_JP* | *_KR* | *_MX* | *_PH* | *_SG* | *_TH* | *_TW*)
        printf '0\n'
        return
        ;;
    esac
  done

  printf '1\n'
}
