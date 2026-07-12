#!/usr/bin/env sh
# Systemd timer/service scan status helper (libredefender / chkrootkit style modules).
#
# check_systemd_scan_service ARGS (positional):
#   1  service_name      systemd unit to probe (e.g. libredefender-scan.service)
#   2  timer_name        stamp-<timer_name>.timer under /var/lib/systemd/timers/
#   3  display_name      tooltip title
#   4  label             short bar text label
#   5  init_icon         glyph while first check runs
#   6  cache_file        Waybar JSON cache path
#   7  lock_dir          refresh lock directory
#   8  ttl               fresh-cache TTL (seconds)
#   9  stale_lock_ttl    when to steal a dead lock
#  10  stale_scan_ttl    seconds since last stamp → "stale" warning
#  11  stale_scan_text   status string when scan is stale
#  12  click_hint        tooltip click instructions
#  13  script_path       $0 of the status script (for background --refresh)
#  14  is_refresh        optional "--refresh" (else serve/cache / scanning UI)
#
# When the service is active/activating, emit a scanning frame and spawn a
# background waiter that --refresh-es once the unit leaves active|activating.
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
  printf '%s\n' "$json" >"$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
}
