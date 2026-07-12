#!/usr/bin/env bash
# Weather status for Waybar. Prefers Open-Meteo; falls back to wttr.in.
# Temps via waybar-locale-lib.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/weather-status.json"
lock_dir="$cache_dir/weather-status.lock.d"
geo_cache="$cache_dir/weather-geo.json"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

ttl="$(waybar_module_interval weather 1800)"
stale_lock_ttl=30
mkdir -p "$cache_dir"

weather_unit=$(detect_weather_unit)
weather_location=$(waybar_settings_get '.weather.location' '')
provider=$(waybar_settings_get '.weather.provider' 'auto')
lat_cfg=$(waybar_settings_get '.weather.latitude' '')
lon_cfg=$(waybar_settings_get '.weather.longitude' '')

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

wmo_icon() {
  # WMO weather interpretation codes → nerd icons
  local code="${1:-0}"
  case "$code" in
    0) printf '󰖙' ;;
    1 | 2) printf '󰖕' ;;
    3) printf '󰖐' ;;
    45 | 48) printf '󰖑' ;;
    51 | 53 | 55 | 56 | 57 | 61 | 63 | 65 | 66 | 67 | 80 | 81 | 82) printf '󰖗' ;;
    71 | 73 | 75 | 77 | 85 | 86) printf '󰼶' ;;
    95 | 96 | 99) printf '󰖓' ;;
    *) printf '󰖐' ;;
  esac
}

resolve_coords() {
  if [ -n "$lat_cfg" ] && [ "$lat_cfg" != "null" ] && [ -n "$lon_cfg" ] && [ "$lon_cfg" != "null" ]; then
    printf '%s %s' "$lat_cfg" "$lon_cfg"
    return 0
  fi

  local loc=""
  if [ -n "$weather_location" ] && [ "$weather_location" != "null" ] && [ "$weather_location" != "auto" ]; then
    loc="$weather_location"
    local geo
    geo=$(curl -s --max-time 8 \
      "https://geocoding-api.open-meteo.com/v1/search?name=$(printf '%s' "$loc" | jq -sRr @uri)&count=1" 2>/dev/null || true)
    lat=$(printf '%s' "$geo" | jq -r '.results[0].latitude // empty' 2>/dev/null || true)
    lon=$(printf '%s' "$geo" | jq -r '.results[0].longitude // empty' 2>/dev/null || true)
    if [ -n "$lat" ] && [ -n "$lon" ]; then
      printf '%s %s' "$lat" "$lon"
      return 0
    fi
  fi

  # IP geolocation fallback (cached 1 day)
  if [ -f "$geo_cache" ] && [ "$(cache_file_age "$geo_cache")" -le 86400 ] 2>/dev/null; then
    lat=$(jq -r '.latitude // empty' "$geo_cache" 2>/dev/null || true)
    lon=$(jq -r '.longitude // empty' "$geo_cache" 2>/dev/null || true)
    if [ -n "$lat" ] && [ -n "$lon" ]; then
      printf '%s %s' "$lat" "$lon"
      return 0
    fi
  fi

  local ipgeo
  ipgeo=$(curl -s --max-time 8 "https://ipapi.co/json/" 2>/dev/null || true)
  lat=$(printf '%s' "$ipgeo" | jq -r '.latitude // empty' 2>/dev/null || true)
  lon=$(printf '%s' "$ipgeo" | jq -r '.longitude // empty' 2>/dev/null || true)
  if [ -n "$lat" ] && [ -n "$lon" ]; then
    printf '%s\n' "$ipgeo" >"$geo_cache" 2>/dev/null || true
    printf '%s %s' "$lat" "$lon"
    return 0
  fi
  return 1
}

fetch_open_meteo() {
  local coords lat lon
  coords=$(resolve_coords) || return 1
  lat=${coords%% *}
  lon=${coords##* }
  curl -s --max-time 10 \
    "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,precipitation&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=3" \
    >"$1" || return 1
  jq -e '.current.temperature_2m != null' "$1" >/dev/null 2>&1
}

fetch_wttr() {
  local loc=""
  if [ -n "$weather_location" ] && [ "$weather_location" != "null" ] && [ "$weather_location" != "auto" ]; then
    loc="$weather_location"
  fi
  curl -s --max-time 10 "https://wttr.in/$loc?format=j1" >"$1" || return 1
  jq -e '.current_condition[0].temp_C != null' "$1" >/dev/null 2>&1
}

emit_from_open_meteo() {
  local raw="$1"
  local parsed
  parsed=$(printf '%s' "$raw" | jq -c '
    def as_int($v): ($v // 0 | tonumber? // 0) | round;
    . as $root |
    .current as $c |
    {
      icon_code: ($c.weather_code // 0),
      temp_c: as_int($c.temperature_2m),
      humidity: (($c.relative_humidity_2m // 0) | tostring),
      wind_kmph: (as_int($c.wind_speed_10m) | tostring),
      precip_mm: (($c.precipitation // 0) | tostring),
      forecast: [
        range(0; 3) |
        {
          label: (if . == 0 then "Today:    " elif . == 1 then "Tomorrow: " else "Day After:" end),
          code: ($root.daily.weather_code[.] // 0),
          min_c: as_int($root.daily.temperature_2m_min[.]),
          max_c: as_int($root.daily.temperature_2m_max[.])
        }
      ]
    }
  ' 2>/dev/null || echo "")
  [ -n "$parsed" ] && [ "$parsed" != "null" ] || return 1

  local icon_code temp_c humidity wind_kmph precip_mm
  icon_code=$(printf '%s' "$parsed" | jq -r '.icon_code')
  temp_c=$(printf '%s' "$parsed" | jq -r '.temp_c')
  humidity=$(printf '%s' "$parsed" | jq -r '.humidity')
  wind_kmph=$(printf '%s' "$parsed" | jq -r '.wind_kmph')
  precip_mm=$(printf '%s' "$parsed" | jq -r '.precip_mm')
  local icon
  icon=$(wmo_icon "$icon_code")

  local wind_miles
  wind_miles=$(awk -v k="$wind_kmph" 'BEGIN { printf "%d", (k * 0.621371) + 0.5 }')
  local precip_in
  precip_in=$(awk -v m="$precip_mm" 'BEGIN { printf "%.2f", m / 25.4 }')

  local temp_short temp_tooltip wind_tooltip precip_tooltip
  temp_short=$(format_locale_temp "$temp_c" short | tr -d '\n')
  temp_tooltip=$(format_locale_temp "$temp_c" both | tr -d '\n')
  if [ "$use_metric" -eq 1 ]; then
    wind_tooltip="${wind_kmph} km/h (${wind_miles} mph)"
    precip_tooltip="${precip_mm} mm (${precip_in} in)"
  else
    wind_tooltip="${wind_miles} mph (${wind_kmph} km/h)"
    precip_tooltip="${precip_in} in (${precip_mm} mm)"
  fi

  local forecast_lines="" label code min_c max_c min_fmt max_fmt day_icon line
  while IFS="$(printf '\t')" read -r label code min_c max_c; do
    [ -n "${label:-}" ] || continue
    day_icon=$(wmo_icon "$code")
    min_fmt=$(format_locale_temp "$min_c" short | tr -d '\n')
    max_fmt=$(format_locale_temp "$max_c" short | tr -d '\n')
    line="${label} ${day_icon} (${min_fmt} - ${max_fmt})"
    if [ -z "$forecast_lines" ]; then
      forecast_lines="$line"
    else
      forecast_lines=$(printf '%s\n%s' "$forecast_lines" "$line")
    fi
  done <<EOF
$(printf '%s' "$parsed" | jq -r '.forecast[] | [.label, (.code|tostring), (.min_c|tostring), (.max_c|tostring)] | @tsv')
EOF

  local text tooltip json
  text="${icon} ${temp_short}"
  tooltip=$(printf 'Current Weather (Open-Meteo)\nTemperature: %s\nWind: %s\nHumidity: %s%%\nPrecipitation: %s\n\n%s\n\nLeft: open-meteo.com · Right: weather.com · Middle: refresh' \
    "$temp_tooltip" "$wind_tooltip" "$humidity" "$precip_tooltip" "$forecast_lines")
  json=$(emit_waybar_json "$text" "$tooltip" "normal")
  printf '%s\n' "$json"
  printf '%s\n' "$json" >"$cache_file.tmp.$$"
  mv -f "$cache_file.tmp.$$" "$cache_file"
}

emit_from_wttr() {
  local raw_weather="$1"
  local parsed
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

  [ -n "$parsed" ] && [ "$parsed" != "null" ] || return 1

  local icon temp_c desc humidity wind_kmph wind_miles precip_mm precip_in
  icon=$(printf '%s' "$parsed" | jq -r '.icon')
  temp_c=$(printf '%s' "$parsed" | jq -r '.temp_c')
  desc=$(printf '%s' "$parsed" | jq -r '.desc')
  humidity=$(printf '%s' "$parsed" | jq -r '.humidity')
  wind_kmph=$(printf '%s' "$parsed" | jq -r '.wind_kmph')
  wind_miles=$(printf '%s' "$parsed" | jq -r '.wind_miles')
  precip_mm=$(printf '%s' "$parsed" | jq -r '.precip_mm')
  precip_in=$(printf '%s' "$parsed" | jq -r '.precip_in')

  local temp_short temp_tooltip wind_tooltip precip_tooltip
  temp_short=$(format_locale_temp "$temp_c" short | tr -d '\n')
  temp_tooltip=$(format_locale_temp "$temp_c" both | tr -d '\n')
  if [ "$use_metric" -eq 1 ]; then
    wind_tooltip="${wind_kmph} km/h (${wind_miles} mph)"
    precip_tooltip="${precip_mm} mm (${precip_in} in)"
  else
    wind_tooltip="${wind_miles} mph (${wind_kmph} km/h)"
    precip_tooltip="${precip_in} in (${precip_mm} mm)"
  fi

  local forecast_lines="" label day_desc min_c max_c min_fmt max_fmt line
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

  local text tooltip json
  text="${icon} ${temp_short}"
  tooltip=$(printf 'Current Weather (wttr.in)\nTemperature: %s\nConditions: %s\nWind: %s\nHumidity: %s%%\nPrecipitation: %s\n\n%s\n\nLeft: wttr.in · Right: weather.com · Middle: refresh' \
    "$temp_tooltip" "$desc" "$wind_tooltip" "$humidity" "$precip_tooltip" "$forecast_lines")
  json=$(emit_waybar_json "$text" "$tooltip" "normal")
  printf '%s\n' "$json"
  printf '%s\n' "$json" >"$cache_file.tmp.$$"
  mv -f "$cache_file.tmp.$$" "$cache_file"
}

tmp_weather=$(mktemp)

try_open_meteo() {
  fetch_open_meteo "$tmp_weather"
}

try_wttr() {
  fetch_wttr "$tmp_weather"
}

used=""
if [ "$provider" = "wttr" ]; then
  animate_command moon "Fetching weather..." "Connecting to wttr.in..." try_wttr && used="wttr" || true
elif [ "$provider" = "open-meteo" ]; then
  animate_command moon "Fetching weather..." "Connecting to Open-Meteo..." try_open_meteo && used="open-meteo" || true
else
  # auto: Open-Meteo first, wttr fallback (also keeps CI wttr fixtures working)
  if animate_command moon "Fetching weather..." "Connecting to Open-Meteo..." try_open_meteo; then
    used="open-meteo"
  elif animate_command moon "Fetching weather..." "Connecting to wttr.in..." try_wttr; then
    used="wttr"
  fi
fi

raw_weather=$(cat "$tmp_weather" 2>/dev/null || echo "")
rm -f "$tmp_weather"

if [ -z "$used" ] || [ -z "$raw_weather" ]; then
  if [ -f "$cache_file" ]; then
    exit 0
  fi
  emit_waybar_json "󰖐 ??" "Weather service temporarily unavailable" "disabled"
  exit 0
fi

if [ "$used" = "open-meteo" ]; then
  emit_from_open_meteo "$raw_weather" || {
    if [ -f "$cache_file" ]; then exit 0; fi
    emit_waybar_json "󰖐 ??" "Weather data parsing failed" "disabled"
  }
else
  emit_from_wttr "$raw_weather" || {
    if [ -f "$cache_file" ]; then exit 0; fi
    emit_waybar_json "󰖐 ??" "Weather data parsing failed" "disabled"
  }
fi
