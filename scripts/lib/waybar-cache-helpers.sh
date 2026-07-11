#!/usr/bin/env sh
# Shared cache helpers for Waybar status scripts.

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
waybar_module_interval() {
  # Usage: waybar_module_interval <key> [fallback]
  # Reads module_intervals from compiled settings JSON.
  # "once" → long cache TTL (signal-driven modules should not be re-probed by libraries).
  key="$1"
  fallback="${2:-60}"
  settings="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/waybar-settings.json"
  if [ ! -f "$settings" ] || ! command -v jq >/dev/null 2>&1; then
    printf '%s' "$fallback"
    return
  fi
  val="$(jq -r --arg k "$key" --argjson fb "$fallback" '
    (.module_intervals[$k] // .poll_intervals[$k] // $fb) as $v
    | if ($v|type) == "number" then $v
      elif $v == "once" then 86400
      else $fb end
  ' "$settings" 2>/dev/null || printf '%s' "$fallback")"
  printf '%s' "$val"
}

cache_file_age() {
  file="$1"
  [ -f "$file" ] || { printf '%s' 999999; return; }
  if [ -n "${BASH_VERSION:-}" ] && [ -n "${EPOCHSECONDS:-}" ]; then
    now="$EPOCHSECONDS"
  else
    now=$(date +%s)
  fi
  mtime=$(stat -c %Y "$file" 2>/dev/null || printf '%s' 0)
  printf '%s' $((now - mtime))
}

read_fresh_cache_file() {
  file="$1"
  ttl="$2"
  age=$(cache_file_age "$file")
  [ "$age" -le "$ttl" ] 2>/dev/null || return 1
  cat "$file"
}

cleanup_stale_tmp_files() {
  dir="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar}"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name '*.tmp.*' -mtime +0 -delete 2>/dev/null || true
}

cleanup_stale_lock_dir() {
  lock_dir="$1"
  stale_lock_ttl="${2:-30}"

  [ -d "$lock_dir" ] || return 0

  lock_pid_file="$lock_dir/pid"
  lock_pid=""
  if [ -f "$lock_pid_file" ]; then
    lock_pid=$(sed -n '1p' "$lock_pid_file" 2>/dev/null || true)
  fi

  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    return 0
  fi

  if [ -n "$lock_pid" ] || [ -f "$lock_pid_file" ]; then
    rm -f "$lock_pid_file"
    rmdir "$lock_dir" 2>/dev/null || true
    return 0
  fi

  now=$(date +%s)
  lock_mtime=$(stat -c %Y "$lock_dir" 2>/dev/null || printf '%s' 0)
  [ $((now - lock_mtime)) -gt "$stale_lock_ttl" ] 2>/dev/null || return 0

  rmdir "$lock_dir" 2>/dev/null || true
}

cleanup_side_info_refresh_locks() {
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-side-graphs/cache"
  stale_lock_ttl=30

  cleanup_stale_lock_dir "$cache_dir/system-refresh.lock.d" "$stale_lock_ttl"
  cleanup_stale_lock_dir "$cache_dir/network-refresh.lock.d" "$stale_lock_ttl"
}

escape_markup() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

json_escape() {
  printf '%s' "$1" | awk 'BEGIN{RS=""; ORS=""} {
    gsub(/\\/, "\\\\")
    gsub(/"/, "\\\"")
    gsub(/\n/, "\\n")
    printf "%s", $0
  }'
}

emit_waybar_json() {
  local text="$1"
  local tooltip="$2"
  local class="${3:-normal}"

  # Expand backslash-n (\n) to real newlines
  local tooltip_expanded
  tooltip_expanded=$(printf '%b' "$tooltip")

  # Escape Pango/XML markup
  local esc_text
  esc_text=$(escape_markup "$text")
  local esc_tooltip
  esc_tooltip=$(escape_markup "$tooltip_expanded")

  # Output as JSON using jq
  jq -cn \
    --arg text "$esc_text" \
    --arg tooltip "$esc_tooltip" \
    --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

refresh_in_background() {
  local_lock_dir="${1:-$lock_dir}"
  local_script_path="${2:-$0}"

  mkdir "$local_lock_dir" 2>/dev/null || return 0
  (
    lock_pid_file="$local_lock_dir/pid"
    cleanup_lock() {
      rm -f "$lock_pid_file"
      rmdir "$local_lock_dir" 2>/dev/null || true
    }
    trap cleanup_lock EXIT INT TERM
    WAYBAR_BACKGROUND=1 "$local_script_path" --refresh >/dev/null 2>&1 || true
  ) >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$local_lock_dir/pid"
}

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
      *%r*|*%I*|*%p*)
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
      *%d*%m*|*%d*%b*|*%d*%B*|*%e*%m*|*%e*%b*|*%e*%B*)
        printf 'day-first\n'
        return
        ;;
      *%m*%d*|*%b*%d*|*%B*%d*|*%m*%e*|*%b*%e*|*%B*%e*)
        printf 'month-first\n'
        return
        ;;
    esac
  fi
  printf 'day-first\n'
}

detect_weather_unit() {
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
      *_US*|*_LR*|*_MM*)
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
    date-only|date-only-long)
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
      *_US*|*_CA*|*_IL*|*_IN*|*_JM*|*_JP*|*_KR*|*_MX*|*_PH*|*_SG*|*_TH*|*_TW*)
        printf '0\n'
        return
        ;;
    esac
  done
  
  printf '1\n'
}

serve_cache_or_refresh() {
  local cache_file="$1"
  local ttl="$2"
  local lock_dir="$3"
  local stale_lock_ttl="$4"
  local script_path="${5:-$0}"

  if [ -f "$cache_file" ] && [ "$(cache_file_age "$cache_file")" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    return 0
  fi

  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"
  [ -d "$lock_dir" ] || refresh_in_background "$lock_dir" "$script_path"

  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi
  return 1
}

serve_metrics_cache_or_refresh() {
  local cached_file="$1"
  local ttl="$2"
  local cache_dir="$3"
  local script_dir="$4"

  if [ -f "$cached_file" ] && [ "$(cache_file_age "$cached_file")" -le "$ttl" ] 2>/dev/null; then
    cat "$cached_file"
    return 0
  fi

  if [ -f "$cached_file" ]; then
    cat "$cached_file"
    if [ ! -d "$cache_dir/system-metrics.lock.d" ]; then
      "$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" --refresh >/dev/null 2>&1 &
    fi
    return 0
  fi
  return 1
}

check_systemd_scan_service() {
  local service_name="$1"
  local timer_name="$2"
  local display_name="$3"
  local label="$4"
  local init_icon="$5"
  local cache_file="$6"
  local lock_dir="$7"
  local ttl="$8"
  local stale_lock_ttl="$9"
  local stale_scan_ttl="${10}"
  local stale_scan_text="${11}"
  local click_hint="${12}"
  local script_path="${13}"
  local is_refresh="${14:-}"

  if [ "$is_refresh" != "--refresh" ]; then
    # Non-blocking: if a scan is active, emit one "scanning" frame and refresh later.
    local active_state
    active_state=$(timeout 2 systemctl show -p ActiveState "$service_name" 2>/dev/null | awk -F= '{print $2}')
    if [ "$active_state" = "active" ] || [ "$active_state" = "activating" ]; then
      : "${WAYBAR_SCRIPTS:=${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts}"
      if [ -f "$WAYBAR_SCRIPTS/lib/unicode-animations-lib.sh" ]; then
        . "$WAYBAR_SCRIPTS/lib/unicode-animations-lib.sh"
      fi

      local last_scan_date="N/A"
      local stamp_file="/var/lib/systemd/timers/stamp-${timer_name}.timer"
      if [ -f "$stamp_file" ]; then
        last_scan_date=$(format_locale_datetime "$(stat -c %Y "$stamp_file")")
      fi

      local spinner="󰑐"
      if command -v get_anim_frame >/dev/null 2>&1; then
        spinner=$(get_anim_frame "dots" 0)
      fi
      emit_waybar_json "$spinner $label" "${display_name}\nStatus: Scanning...\nLast Scan: $last_scan_date\n\nScan is running in background..." "scanning"
      # Background refresh will replace cache when the scan finishes.
      (
        while timeout 2 systemctl show -p ActiveState "$service_name" 2>/dev/null | awk -F= '{print $2}' \
          | grep -Eq '^(active|activating)$'; do
          sleep 2
        done
        "$script_path" --refresh >/dev/null 2>&1 || true
      ) &
      exit 0
    fi

    if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl" "$script_path"; then
      exit 0
    fi

    emit_waybar_json "${init_icon} ${label}" "Checking ${label}..." "normal"
    exit 0
  fi

  # --refresh mode
  local stamp_file="/var/lib/systemd/timers/stamp-${timer_name}.timer"
  local elapsed=-1
  local last_scan_date="Never"
  local ago="N/A"
  if [ -f "$stamp_file" ]; then
    local last_scan_time
    last_scan_time=$(stat -c %Y "$stamp_file")
    last_scan_date=$(format_locale_datetime "$last_scan_time")
    local now
    now=$(date +%s)
    elapsed=$((now - last_scan_time))
    if [ "$elapsed" -lt 60 ]; then
      ago="${elapsed}s ago"
    elif [ "$elapsed" -lt 3600 ]; then
      ago="$((elapsed / 60))m ago"
    elif [ "$elapsed" -lt 86400 ]; then
      ago="$((elapsed / 3600))h ago"
    else
      ago="$((elapsed / 86400))d ago"
    fi
  fi

  local active_state="inactive"
  local result_state="success"
  local exit_code="0"

  while IFS='=' read -r key val; do
    case "$key" in
      ActiveState) active_state="$val" ;;
      Result) result_state="$val" ;;
      ExecMainStatus) exit_code="$val" ;;
    esac
  done <<EOF
$(timeout 2 systemctl show -p ActiveState -p Result -p ExecMainStatus "$service_name" 2>/dev/null)
EOF

  local status_text="Inactive"
  local class="normal"
  local icon="󰱠" # shield-check

  if [ "$active_state" = "active" ] || [ "$active_state" = "activating" ]; then
    status_text="Scanning"
    class="scanning"
    icon="󰑐" # loading/spinning icon
  elif [ "$result_state" = "failed" ] || { [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ] 2>/dev/null; }; then
    status_text="Failed / Threat Found"
    class="critical"
    icon="󰦃" # shield-alert
  elif [ "$elapsed" -eq -1 ]; then
    status_text="Never Scanned"
    class="warning"
    icon="󰒃"
  elif [ "$elapsed" -gt "$stale_scan_ttl" ]; then
    status_text="$stale_scan_text"
    class="warning"
    icon="󰒃"
  fi

  local text
  text=$(printf '%s %s' "$icon" "$label")
  local tooltip
  tooltip=$(printf '%s\nStatus: %s\nLast Scan: %s (%s)\nResult: %s\n\n%s' \
    "$display_name" "$status_text" "$last_scan_date" "$ago" "$result_state" "$click_hint")

  local json
  json=$(emit_waybar_json "$text" "$tooltip" "$class")

  printf '%s\n' "$json"

  local tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" > "$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
}


