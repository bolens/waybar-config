#!/usr/bin/env bash
# Weather status for Waybar (wttr.in). Temps via waybar-locale-lib.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/weather-status.json"
lock_dir="$cache_dir/weather-status.lock.d"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

ttl="$(waybar_module_interval weather 1800)"
stale_lock_ttl=30
mkdir -p "$cache_dir"

weather_unit=$(detect_weather_unit)
weather_location=$(waybar_settings_get '.weather.location' '')

# Prefer metric (km/h, mm) when Celsius is preferred; imperial otherwise.
use_metric=1
[ "$weather_unit" = "F" ] && use_metric=0

if [ "${1:-}" != "--refresh" ]; then
  if [ -f "$cache_file" ] && [ "$(cache_file_age "$cache_file")" -le "$ttl" ] 2>/dev/null; then
    if jq -e --arg unit "°$weather_unit" '.text | endswith($unit)' "$cache_file" >/dev/null 2>&1; then
      cat "$cache_file"
      exit 0
    fi
  fi

  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"
  [ -d "$lock_dir" ] || refresh_in_background

  if [ -f "$cache_file" ]; then
    if jq -e --arg unit "°$weather_unit" '.text | endswith($unit)' "$cache_file" >/dev/null 2>&1; then
      cat "$cache_file"
      exit 0
    fi
  fi

  emit_waybar_json "󰖐 --°$weather_unit" "Loading weather forecast..." "normal"
  exit 0
fi

# --refresh mode
# shellcheck source=unicode-animations-lib.sh
. "$WAYBAR_SCRIPTS/lib/unicode-animations-lib.sh"

fetch_weather_raw() {
  local loc=""
  if [ -n "$weather_location" ] && [ "$weather_location" != "null" ] && [ "$weather_location" != "auto" ]; then
    loc="$weather_location"
  fi
  curl -s --max-time 10 "https://wttr.in/$loc?format=j1" >"$1" || true
}

tmp_weather=$(mktemp)
animate_command moon "Fetching weather..." "Connecting to wttr.in..." fetch_weather_raw "$tmp_weather"
raw_weather=$(cat "$tmp_weather" 2>/dev/null || echo "")
rm -f "$tmp_weather"

if [ -z "$raw_weather" ]; then
  if [ -f "$cache_file" ]; then
    exit 0
  fi
  emit_waybar_json "󰖐 ??" "Weather service temporarily unavailable" "disabled"
  exit 0
fi

# jq extracts structured fields only; shell owns locale-aware temp strings.
parsed=$(printf '%s' "$raw_weather" | jq -c '
  def map_icon($code):
    if $code == "113" then "󰖙"
    elif $code == "116" then "󰖕"
    elif ($code == "119" or $code == "122") then "󰖐"
    elif ($code == "143" or $code == "248" or $code == "260") then "󰖑"
    elif ($code == "176" or $code == "263" or $code == "266" or $code == "293" or $code == "296") then "󰖗"
    elif ($code == "299" or $code == "302" or $code == "305" or $code == "308" or $code == "353" or $code == "356") then "󰖖"
    elif ($code == "179" or $code == "182" or $code == "185" or $code == "227" or $code == "230" or $code == "323" or $code == "326" or $code == "329" or $code == "332" or $code == "335" or $code == "338" or $code == "350" or $code == "368" or $code == "371" or $code == "395") then "󰼶"
    elif ($code == "200" or $code == "386" or $code == "389" or $code == "392") then "󰖓"
    else "󰖐"
    end;

  def as_int($v):
    ($v // "0" | tonumber? // 0) | round;

  . as $root |
  .current_condition[0] as $cc |
  {
    icon: map_icon($cc.weatherCode // "119"),
    temp_c: as_int($cc.temp_C),
    desc: ($cc.weatherDesc[0].value // "" | sub("^\\s+"; "") | sub("\\s+$"; "")),
    humidity: ($cc.humidity // "0"),
    wind_kmph: ($cc.windspeedKmph // "0"),
    wind_miles: ($cc.windspeedMiles // "0"),
    precip_mm: ($cc.precipMM // "0.0"),
    precip_in: ($cc.precipInches // "0.0"),
    forecast: [
      range(0; 3) |
      $root.weather[.] as $w |
      select($w != null) |
      {
        label: (if . == 0 then "Today:    " elif . == 1 then "Tomorrow: " else "Day After:" end),
        desc: ($w.hourly[4].weatherDesc[0].value // "" | sub("^\\s+"; "") | sub("\\s+$"; "")),
        min_c: as_int($w.mintempC),
        max_c: as_int($w.maxtempC)
      }
    ]
  }
' 2>/dev/null || echo "")

if [ -z "$parsed" ] || [ "$parsed" = "null" ]; then
  if [ -f "$cache_file" ]; then
    exit 0
  fi
  emit_waybar_json "󰖐 ??" "Weather data parsing failed" "disabled"
  exit 0
fi

icon=$(printf '%s' "$parsed" | jq -r '.icon')
temp_c=$(printf '%s' "$parsed" | jq -r '.temp_c')
desc=$(printf '%s' "$parsed" | jq -r '.desc')
humidity=$(printf '%s' "$parsed" | jq -r '.humidity')
wind_kmph=$(printf '%s' "$parsed" | jq -r '.wind_kmph')
wind_miles=$(printf '%s' "$parsed" | jq -r '.wind_miles')
precip_mm=$(printf '%s' "$parsed" | jq -r '.precip_mm')
precip_in=$(printf '%s' "$parsed" | jq -r '.precip_in')

temp_short=$(format_locale_temp "$temp_c" short | tr -d '\n')
temp_tooltip=$(format_locale_temp "$temp_c" both | tr -d '\n')

if [ "$use_metric" -eq 1 ]; then
  wind_tooltip="${wind_kmph} km/h (${wind_miles} mph)"
  precip_tooltip="${precip_mm} mm (${precip_in} in)"
else
  wind_tooltip="${wind_miles} mph (${wind_kmph} km/h)"
  precip_tooltip="${precip_in} in (${precip_mm} mm)"
fi

forecast_lines=""
while IFS="$(printf '\t')" read -r label day_desc min_c max_c; do
  [ -n "${label:-}" ] || continue
  min_fmt=$(format_locale_temp "$min_c" short | tr -d '\n')
  max_fmt=$(format_locale_temp "$max_c" short | tr -d '\n')
  line="${label} ${day_desc} (${min_fmt} - ${max_fmt})"
  if [ -z "$forecast_lines" ]; then
    forecast_lines="$line"
  else
    forecast_lines=$(printf '%s\n%s' "$forecast_lines" "$line")
  fi
done <<EOF
$(printf '%s' "$parsed" | jq -r '.forecast[] | [.label, .desc, (.min_c|tostring), (.max_c|tostring)] | @tsv')
EOF

text="${icon} ${temp_short}"
tooltip=$(printf 'Current Weather\nTemperature: %s\nConditions: %s\nWind: %s\nHumidity: %s%%\nPrecipitation: %s\n\n%s\n\nLeft: wttr.in · Right: weather.com · Middle: refresh' \
  "$temp_tooltip" "$desc" "$wind_tooltip" "$humidity" "$precip_tooltip" "$forecast_lines")

json=$(emit_waybar_json "$text" "$tooltip" "normal")
printf '%s\n' "$json"
tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
