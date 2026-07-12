#!/usr/bin/env sh
# Shared brightness collection for Waybar status + listener.
set -eu

brightness_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
brightness_state_file="$brightness_cache_dir/brightness-ddc-displays"
brightness_cache_file="$brightness_cache_dir/brightness-status.json"

# Settings helpers: callers (bash) may already provide waybar_settings_get.
# Under plain sh, resolve via a short bash helper to avoid sourcing bashisms.
_brightness_lib_dir="${WAYBAR_SCRIPTS:-${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts}/lib}"
if ! type waybar_css_class_for_output >/dev/null 2>&1; then
  if [ -f "$_brightness_lib_dir/output-lib.sh" ]; then
    # shellcheck source=output-lib.sh
    . "$_brightness_lib_dir/output-lib.sh"
  fi
fi

_brightness_settings_get() {
  _path="$1"
  _default="$2"
  if type waybar_settings_get >/dev/null 2>&1; then
    waybar_settings_get "$_path" "$_default"
    return 0
  fi
  if [ -f "$_brightness_lib_dir/waybar-settings.sh" ] && command -v bash >/dev/null 2>&1; then
    bash -c 'WAYBAR_HOME="$1"; WAYBAR_SCRIPTS="$2"; . "$2/lib/waybar-settings.sh"; waybar_settings_get "$3" "$4"' \
      _ "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}" \
      "${WAYBAR_SCRIPTS:-${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts}" \
      "$_path" "$_default" 2>/dev/null || printf '%s' "$_default"
    return 0
  fi
  printf '%s' "$_default"
}

brightness_per_output_enabled() {
  _val=$(_brightness_settings_get '.brightness.per_output' 'true')
  case "$_val" in
    false | False | FALSE | 0 | no | No | NO | null | off | Off | OFF) return 1 ;;
    *) return 0 ;;
  esac
}

# Set brightness_cache_file (and related pending paths via BRIGHTNESS_OUTPUT_SAFE) for an output.
brightness_bind_output() {
  _out="${1:-${WAYBAR_OUTPUT_NAME:-}}"
  if [ -n "$_out" ] && brightness_per_output_enabled; then
    if type waybar_css_class_for_output >/dev/null 2>&1; then
      BRIGHTNESS_OUTPUT_SAFE=$(waybar_css_class_for_output "$_out")
    else
      BRIGHTNESS_OUTPUT_SAFE=$(printf '%s' "$_out" | sed 's/[^A-Za-z0-9_-]/_/g')
    fi
    brightness_cache_file="$brightness_cache_dir/brightness-status-${BRIGHTNESS_OUTPUT_SAFE}.json"
    export WAYBAR_OUTPUT_NAME="$_out"
  else
    BRIGHTNESS_OUTPUT_SAFE=""
    brightness_cache_file="$brightness_cache_dir/brightness-status.json"
  fi
}

# Resolve control/status target for OUTPUT.
# Prints: backlight | backlight:NAME | ddc:N | legacy
brightness_resolve_target() {
  _out="${1:-${WAYBAR_OUTPUT_NAME:-}}"

  if [ -z "$_out" ] || ! brightness_per_output_enabled; then
    printf 'legacy\n'
    return 0
  fi

  # 1) Explicit pin from brightness.output_map
  _pin=""
  if command -v jq >/dev/null 2>&1; then
    _map=$(_brightness_settings_get '.brightness.output_map' '{}')
    _pin=$(printf '%s' "$_map" | jq -r --arg o "$_out" '.[$o] // empty' 2>/dev/null || true)
  fi
  if [ -n "$_pin" ] && [ "$_pin" != "null" ]; then
    printf '%s\n' "$_pin"
    return 0
  fi

  # 2) Heuristic: internal panels → backlight; external → DDC
  case "$_out" in
    eDP* | EDP* | LVDS* | lvds* | DSI*)
      _bl=$(brightnessctl --class=backlight -m 2>/dev/null | head -n1 | cut -d, -f1 || true)
      if [ -n "$_bl" ]; then
        printf 'backlight:%s\n' "$_bl"
      else
        printf 'backlight\n'
      fi
      return 0
      ;;
  esac

  if command -v ddcutil >/dev/null 2>&1; then
    _ids=""
    if [ -f "$brightness_state_file" ]; then
      _ids=$(cat "$brightness_state_file" 2>/dev/null || true)
    fi
    if [ -z "$_ids" ]; then
      _ids=$(brightness_get_detected_ids)
    fi
    _first=$(printf '%s' "$_ids" | awk '{print $1}')
    if [ -n "$_first" ]; then
      printf 'ddc:%s\n' "$_first"
      return 0
    fi
  fi

  # 3) Legacy average / first-available path
  printf 'legacy\n'
}

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
  tooltip=$(printf 'Brightness source: %s\nAverage brightness: %s%%%s\n\nLeft: dim · Right: brighten · Middle: 80%%' "$source_name" "$percent" "$tooltip_lines")
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
  if type with_ddcutil_lock >/dev/null 2>&1; then
    with_ddcutil_lock ddcutil detect --brief 2>/dev/null \
      | sed -n 's/^Display \([0-9][0-9]*\)$/\1/p' \
      | xargs 2>/dev/null || true
  else
    ddcutil detect --brief 2>/dev/null \
      | sed -n 's/^Display \([0-9][0-9]*\)$/\1/p' \
      | xargs 2>/dev/null || true
  fi
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

brightness_collect_backlight_device() {
  # Optional device name; empty → all backlights (legacy average).
  want="${1:-}"
  if [ -n "$want" ]; then
    brightnessctl --class=backlight -d "$want" -m 2>/dev/null || true
  else
    brightness_collect_backlight
  fi
}

brightness_collect_status_json() {
  script_dir="${1:-}"
  out_name="${2:-${WAYBAR_OUTPUT_NAME:-}}"
  if [ -n "$script_dir" ] && [ -f "$script_dir/ddcutil-lock.sh" ]; then
    # shellcheck source=ddcutil-lock.sh
    . "$script_dir/ddcutil-lock.sh"
  fi

  mkdir -p "$brightness_cache_dir"
  brightness_bind_output "$out_name"
  target=$(brightness_resolve_target "$out_name")

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

  case "$target" in
    backlight | backlight:*)
      bl_dev=""
      case "$target" in
        backlight:*) bl_dev="${target#backlight:}" ;;
      esac
      backlights=$(brightness_collect_backlight_device "$bl_dev")
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
          src_name="backlight"
          [ -n "$bl_dev" ] && src_name="backlight:$bl_dev"
          [ -n "$out_name" ] && src_name="$src_name ($out_name)"
          brightness_emit_output "$src_name" "$percent" "$tooltip_lines"
          return 0
        fi
      fi
      ;;
    ddc:*)
      display_id="${target#ddc:}"
      if command -v ddcutil >/dev/null 2>&1 && [ -n "$display_id" ]; then
        ddc_info=$(brightness_collect_ddc_from_ids "$display_id" || true)
        if [ -n "$ddc_info" ]; then
          percent=$(printf '%s\n' "$ddc_info" | awk 'BEGIN{p=0} /__SPLIT__/ {p=1; next} p==0 {print}')
          tooltip_lines=$(printf '%s\n' "$ddc_info" | awk 'BEGIN{s=0} /__SPLIT__/ {s=s+1; next} s==1 {print}')
          src_name="DDC/CI:$display_id"
          [ -n "$out_name" ] && src_name="$src_name ($out_name)"
          brightness_emit_output "$src_name" "$percent" "$tooltip_lines"
          return 0
        fi
      fi
      ;;
  esac

  # Legacy / fallback: average all backlights, then all DDC displays.
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
