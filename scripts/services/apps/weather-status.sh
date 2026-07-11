#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/weather-status.json"
lock_dir="$cache_dir/weather-status.lock.d"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
ttl="$(waybar_module_interval weather 1800)"
stale_lock_ttl=30

mkdir -p "$cache_dir"

script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

weather_unit=$(waybar_settings_get '.weather.unit' '')
if [ -z "$weather_unit" ] || [ "$weather_unit" = "auto" ] || [ "$weather_unit" = "null" ]; then
  weather_unit=$(detect_weather_unit)
fi
weather_unit=$(echo "$weather_unit" | tr '[:lower:]' '[:upper:]')
case "$weather_unit" in
  C*) weather_unit="C" ;;
  *) weather_unit="F" ;;
esac

weather_location=$(waybar_settings_get '.weather.location' '')

map_code_to_icon() {
  case "$1" in
    113) printf '󰖙' ;;                                                                                     # Sunny/Clear
    116) printf '󰖕' ;;                                                                                     # Partly Cloudy
    119 | 122) printf '󰖐' ;;                                                                               # Cloudy / Overcast
    143 | 248 | 260) printf '󰖑' ;;                                                                         # Fog / Mist
    176 | 263 | 266 | 293 | 296) printf '󰖗' ;;                                                             # Patchy light rain / Drizzle
    299 | 302 | 305 | 308 | 353 | 356) printf '󰖖' ;;                                                       # Rain / Showers
    179 | 182 | 185 | 227 | 230 | 323 | 326 | 329 | 332 | 335 | 338 | 350 | 368 | 371 | 395) printf '󰼶' ;; # Snow / Sleet
    200 | 386 | 389 | 392) printf '󰖓' ;;                                                                   # Thunder / Storm
    *) printf '󰖐' ;;
  esac
}

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
  # If curl failed, keep the stale cache if available, else show error
  if [ -f "$cache_file" ]; then
    exit 0
  fi
  emit_waybar_json "󰖐 ??" "Weather service temporarily unavailable" "disabled"
  exit 0
fi

# Run single jq invocation to build the entire JSON output
json=$(printf '%s' "$raw_weather" | jq -c --arg unit "$weather_unit" '
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

  . as $root |
  ($unit == "C") as $use_c |

  .current_condition[0] as $cc |
  ($cc.temp_C // "0") as $temp_c |
  ($cc.temp_F // "0") as $temp_f |
  (if $use_c then $temp_c else $temp_f end) as $temp |
  ($cc.weatherDesc[0].value // "" | sub("^\\s+"; "") | sub("\\s+$"; "")) as $desc |
  ($cc.weatherCode // "119") as $code |
  ($cc.humidity // "0") as $humidity |
  ($cc.windspeedKmph // "0") as $wind_kmph |
  ($cc.windspeedMiles // "0") as $wind_miles |
  ($cc.precipMM // "0.0") as $precip_mm |
  ($cc.precipInches // "0.0") as $precip_in |
  map_icon($code) as $icon |

  [
    range(0; 3) |
    $root.weather[.] as $w |
    if $w != null then
      (if . == 0 then "Today:    " elif . == 1 then "Tomorrow: " else "Day After:" end) as $day_label |
      ($w.maxtempC // "0") as $max_c |
      ($w.mintempC // "0") as $min_c |
      ($w.maxtempF // "0") as $max_f |
      ($w.mintempF // "0") as $min_f |
      (if $use_c then "\($min_c)°C - \($max_c)°C" else "\($min_f)°F - \($max_f)°F" end) as $temp_range |
      ($w.hourly[4].weatherDesc[0].value // "" | sub("^\\s+"; "") | sub("\\s+$"; "")) as $day_desc |
      "\($day_label) \($day_desc) (\($temp_range))"
    else
      empty
    end
  ] | join("\n") as $forecast |

  (if $use_c then "\($temp_c)°C (\($temp_f)°F)" else "\($temp_f)°F (\($temp_c)°C)" end) as $temp_tooltip |
  (if $use_c then "\($wind_kmph) km/h (\($wind_miles) mph)" else "\($wind_miles) mph (\($wind_kmph) km/h)" end) as $wind_tooltip |
  (if $use_c then "\($precip_mm) mm (\($precip_in) in)" else "\($precip_in) in (\($precip_mm) mm)" end) as $precip_tooltip |

  "\($icon) \($temp)°\($unit)" as $text |
  "Current Weather\nTemperature: \($temp_tooltip)\nConditions: \($desc)\nWind: \($wind_tooltip)\nHumidity: \($humidity)%\nPrecipitation: \($precip_tooltip)\n\n\($forecast)\n\nLeft: wttr.in · Right: weather.com · Middle: refresh" as $tooltip |

  {text: $text, tooltip: $tooltip, class: "normal"}
' 2>/dev/null || echo "")

if [ -z "$json" ]; then
  # Fallback if jq parsing failed
  if [ -f "$cache_file" ]; then
    exit 0
  fi
  emit_waybar_json "󰖐 ??" "Weather data parsing failed" "disabled"
  exit 0
fi

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
