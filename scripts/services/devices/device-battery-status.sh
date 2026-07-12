#!/usr/bin/env bash
# Waybar status for wireless device batteries (mice/keyboards/gamepads).
# Prefers /sys/class/power_supply Device batteries; falls back to `solaar show`
# when hidpp sysfs entries are missing but Solaar is installed.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/device-battery.json"
lock_dir="$cache_dir/device-battery.lock.d"
ttl="$(waybar_module_interval device_battery 30)"
stale_lock_ttl=45

mkdir -p "$cache_dir"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

batt_warn=$(waybar_settings_get '.thresholds.device_battery.warning' '30')
batt_crit=$(waybar_settings_get '.thresholds.device_battery.critical' '15')

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "" "Initializing device battery..." "none"
  exit 0
fi

pick_icon() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *mouse* | *g502* | *g903* | *g305* | *g603* | *g703* | *g900* | *viper* | *deathadder* | *basilisk* | *trackball*)
      printf '󰍽'
      ;;
    *keyboard* | *g915* | *g613* | *keychron*)
      printf '󰌌'
      ;;
    *controller* | *gamepad* | *joystick* | *xbox* | *dualsense* | *dualshock* | *nintendo* | *sony*)
      printf '󰖺'
      ;;
    *)
      printf '󰂁'
      ;;
  esac
}

# Collect Device-scoped batteries; prefer the lowest capacity (most urgent).
# Test/portability: WAYBAR_POWER_SUPPLY_ROOT overrides /sys/class/power_supply.
power_supply_root="${WAYBAR_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
best_cap=101
best_status="unknown"
best_model=""
best_source=""

for d in "$power_supply_root"/*; do
  [ -d "$d" ] || continue
  type=$(cat "$d/type" 2>/dev/null || true)
  scope=$(cat "$d/scope" 2>/dev/null || true)
  [ "$type" = "Battery" ] && [ "$scope" = "Device" ] || continue
  capacity=$(cat "$d/capacity" 2>/dev/null || echo 0)
  status=$(cat "$d/status" 2>/dev/null || echo "unknown")
  model_name=$(cat "$d/model_name" 2>/dev/null || echo "Wireless Device")
  if [ "$capacity" -lt "$best_cap" ] 2>/dev/null; then
    best_cap=$capacity
    best_status=$status
    best_model=$model_name
    best_source="sysfs"
  fi
done

# Solaar fallback / supplement when no sysfs Device battery (or FORCE)
solaar_bin="${WAYBAR_SOLAAR_BIN:-}"
if [ -z "$solaar_bin" ] && command -v solaar >/dev/null 2>&1; then
  solaar_bin=$(command -v solaar)
fi

if { [ -z "$best_source" ] || [ "${WAYBAR_DEVICE_BATTERY_PREFER_SOLAAR:-0}" = "1" ]; } \
  && [ -n "$solaar_bin" ] && [ -x "$solaar_bin" ]; then
  solaar_out=$(timeout 3 "$solaar_bin" show 2>/dev/null || true)
  if [ -n "$solaar_out" ]; then
    # Parse blocks: device name line then Battery: NN% or "Battery: N/A, ..."
    while IFS= read -r line; do
      case "$line" in
        [0-9]*:* | *:)
          # "1: Device Name" or similar
          cur_name=$(printf '%s' "$line" | sed -E 's/^[0-9]+:[[:space:]]*//; s/[[:space:]]+$//')
          ;;
        *Battery:* | *battery:*)
          pct=$(printf '%s' "$line" | sed -nE 's/.*[Bb]attery:[[:space:]]*([0-9]+)%.*/\1/p')
          st="Discharging"
          printf '%s' "$line" | grep -qiE '(^|[^a-z])charging([^a-z]|$)' && st="Charging"
          printf '%s' "$line" | grep -qi 'discharging' && st="Discharging"
          printf '%s' "$line" | grep -qiE '\bfull\b' && st="Full"
          if [ -n "$pct" ] && [ "$pct" -lt "$best_cap" ] 2>/dev/null; then
            best_cap=$pct
            best_status=$st
            best_model=${cur_name:-Logitech device}
            best_source="solaar"
          fi
          ;;
      esac
    done <<<"$solaar_out"
  fi
fi

if [ -z "$best_source" ] || [ "$best_cap" -gt 100 ] 2>/dev/null; then
  write_cache_and_exit "$(emit_waybar_json "" "No wireless devices connected" "none")"
fi

capacity=$best_cap
status=$best_status
model_name=$best_model
icon=$(pick_icon "$model_name")

class="normal"
if [ "$status" = "Charging" ]; then
  class="charging"
elif [ "$capacity" -le "$batt_crit" ]; then
  class="critical"
elif [ "$capacity" -le "$batt_warn" ]; then
  class="warning"
fi

text=$(printf '%s %d%%' "$icon" "$capacity")
tooltip=$(printf 'Device Battery: %s\nLevel: %d%%\nStatus: %s\nSource: %s\n\nLeft: Solaar · Right: input settings · Middle: refresh' \
  "$model_name" "$capacity" "$status" "$best_source")

write_cache_and_exit "$(emit_waybar_json "$text" "$tooltip" "$class")"
