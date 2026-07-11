#!/usr/bin/env sh
# Shared brightness collection for Waybar status + listener.
set -eu

brightness_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
brightness_state_file="$brightness_cache_dir/brightness-ddc-displays"
brightness_cache_file="$brightness_cache_dir/brightness-status.json"

brightness_emit_output() {
  source_name="$1"
  percent="$2"
  tooltip_lines="$3"

  class="normal"
  if [ "$percent" -le 10 ]; then
    class="critical"
  elif [ "$percent" -le 25 ]; then
    class="warning"
  fi

  icon="󰃞"
  if [ "$percent" -ge 70 ]; then
    icon="󰃠"
  elif [ "$percent" -ge 35 ]; then
    icon="󰃟"
  fi

  if [ -n "$tooltip_lines" ]; then
    tooltip_lines=$(printf '\n%s' "$tooltip_lines")
  fi
  tooltip=$(printf 'Brightness source: %s\nAverage brightness: %s%%%s' "$source_name" "$percent" "$tooltip_lines")
  pct_text=$(printf '%3d' "$percent")
  jq -cn \
    --arg text "$icon ${pct_text}%" \
    --arg tooltip "$tooltip" \
    --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

brightness_collect_backlight() {
  brightnessctl --class=backlight -m 2>/dev/null || true
}

brightness_get_detected_ids() {
  with_ddcutil_lock ddcutil detect --brief 2>/dev/null \
    | sed -n 's/^Display \([0-9][0-9]*\)$/\1/p' \
    | xargs 2>/dev/null || true
}

brightness_collect_ddc_from_ids() {
  input_ids="$1"
  total=0
  count=0
  tooltip_lines=""
  valid_ids=""

  for display_id in $input_ids; do
    line=$(with_ddcutil_lock ddcutil getvcp 10 --brief --display "$display_id" 2>/dev/null | tail -n1 || true)
    case "$line" in
      "VCP 10"*)
        current=$(printf '%s\n' "$line" | awk '{print $(NF-1)}')
        max=$(printf '%s\n' "$line" | awk '{print $NF}')
        [ -n "$current" ] || continue
        [ -n "$max" ] || continue
        [ "$max" -gt 0 ] 2>/dev/null || continue
        percent=$((current * 100 / max))
        total=$((total + percent))
        count=$((count + 1))
        if [ -n "$tooltip_lines" ]; then
          tooltip_lines=$(printf '%s\nDisplay %s: %s%%' "$tooltip_lines" "$display_id" "$percent")
        else
          tooltip_lines=$(printf 'Display %s: %s%%' "$display_id" "$percent")
        fi
        valid_ids="$valid_ids $display_id"
        ;;
    esac
  done

  valid_ids=$(printf '%s' "$valid_ids" | xargs 2>/dev/null || true)
  if [ "$count" -gt 0 ]; then
    average=$((total / count))
    printf '%s\n__SPLIT__\n%s\n__SPLIT__\n%s\n' "$average" "$tooltip_lines" "$valid_ids"
  fi
}

brightness_collect_status_json() {
  script_dir="${1:-}"
  if [ -n "$script_dir" ] && [ -f "$script_dir/ddcutil-lock.sh" ]; then
    # shellcheck source=ddcutil-lock.sh
    . "$script_dir/ddcutil-lock.sh"
  fi

  mkdir -p "$brightness_cache_dir"

  # Skip polling if a game is active to prevent I2C bus locks and SIM spikes
  skip_ddc=0
  if [ -f "$HOME/.local/state/launchlayer/active-launch.pid" ]; then
    active_pid=$(cat "$HOME/.local/state/launchlayer/active-launch.pid" 2>/dev/null || true)
    if [ -n "$active_pid" ] && kill -0 "$active_pid" 2>/dev/null; then
      skip_ddc=1
    fi
  fi
  if [ "$skip_ddc" -eq 0 ]; then
    if pgrep -x "overwatch.exe" >/dev/null 2>&1 || pgrep -x "wine64-preloader" >/dev/null 2>&1 || pgrep -x "proton" >/dev/null 2>&1; then
      skip_ddc=1
    fi
  fi
  if [ "$skip_ddc" -eq 1 ]; then
    if [ -f "$brightness_cache_file" ]; then
      cat "$brightness_cache_file"
      return 0
    fi
    jq -cn \
      --arg text "󰃠 --%" \
      --arg tooltip "Polling paused (gaming mode active)" \
      --arg class "normal" \
      '{text:$text, tooltip:$tooltip, class:$class}'
    return 0
  fi

  backlights=$(brightness_collect_backlight)

  if [ -n "$backlights" ]; then
    total=0
    count=0
    tooltip_lines=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      device=$(printf '%s\n' "$line" | cut -d, -f1)
      percent=$(printf '%s\n' "$line" | cut -d, -f4 | tr -d '%')
      [ -n "$percent" ] || continue
      total=$((total + percent))
      count=$((count + 1))
      if [ -n "$tooltip_lines" ]; then
        tooltip_lines=$(printf '%s\n%s: %s%%' "$tooltip_lines" "$device" "$percent")
      else
        tooltip_lines=$(printf '%s: %s%%' "$device" "$percent")
      fi
    done <<EOF
$backlights
EOF

    if [ "$count" -gt 0 ]; then
      percent=$((total / count))
      brightness_emit_output "backlight" "$percent" "$tooltip_lines"
      return 0
    fi
  fi

  if command -v ddcutil >/dev/null 2>&1; then
    display_ids=""
    if [ -f "$brightness_state_file" ]; then
      display_ids=$(cat "$brightness_state_file" 2>/dev/null || true)
    fi
    if [ -z "$display_ids" ]; then
      display_ids=$(brightness_get_detected_ids)
    fi

    ddc_info=$(brightness_collect_ddc_from_ids "$display_ids" || true)
    if [ -z "$ddc_info" ]; then
      display_ids=$(brightness_get_detected_ids)
      ddc_info=$(brightness_collect_ddc_from_ids "$display_ids" || true)
    fi

    if [ -n "$ddc_info" ]; then
      percent=$(printf '%s\n' "$ddc_info" | awk 'BEGIN{p=0} /__SPLIT__/ {p=1; next} p==0 {print}')
      tooltip_lines=$(printf '%s\n' "$ddc_info" | awk 'BEGIN{s=0} /__SPLIT__/ {s=s+1; next} s==1 {print}')
      valid_ids=$(printf '%s\n' "$ddc_info" | awk 'BEGIN{s=0} /__SPLIT__/ {s=s+1; next} s==2 {print}')

      if [ -n "$valid_ids" ]; then
        tmp_state="${brightness_state_file}.tmp.$$"
        printf '%s\n' "$valid_ids" >"$tmp_state"
        mv -f "$tmp_state" "$brightness_state_file"
      fi

      brightness_emit_output "DDC/CI" "$percent" "$tooltip_lines"
      return 0
    fi
  fi

  jq -cn \
    --arg text "󰃞 --" \
    --arg tooltip "No supported brightness devices found" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

brightness_write_cache() {
  payload="$1"
  tmp="${brightness_cache_file}.tmp.$$"
  printf '%s\n' "$payload" >"$tmp"
  mv "$tmp" "$brightness_cache_file"
}

brightness_state_key() {
  json="$1"
  printf '%s' "$json" | jq -r '[.text, .class] | join(":")'
}
