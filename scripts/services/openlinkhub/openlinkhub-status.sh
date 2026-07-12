#!/usr/bin/env bash
# Waybar status for OpenLinkHub (Corsair iCUE alternative).
# Presence-first: device count on the bar. PSU telemetry prefers corsairpsu hwmon
# (custom/psu) when available — OLH still shows linked devices + UI link.
# Hides (disconnected) when the service is down or the local API is unreachable.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/openlinkhub-status.json"
lock_dir="$cache_dir/openlinkhub-status.lock.d"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
ttl="$(waybar_module_interval openlinkhub 10)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰈐 --" "Initializing OpenLinkHub..." "normal"
  exit 0
fi

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
api_url=$(waybar_settings_get '.services.openlinkhub.api_url' 'http://127.0.0.1:27003')
api_url="${WAYBAR_OLH_API_URL:-$api_url}"
api_url="${api_url%/}"
ui_url=$(waybar_settings_get '.services.openlinkhub.ui_url' "$api_url")
ui_url="${WAYBAR_OLH_UI_URL:-$ui_url}"
service_name=$(waybar_settings_get '.services.openlinkhub.service_name' 'openlinkhub.service')
prefer_presence=$(waybar_settings_get '.services.openlinkhub.prefer_presence' 'true')
temp_warn=$(waybar_settings_get '.thresholds.openlinkhub.temp.warning' '60')
temp_crit=$(waybar_settings_get '.thresholds.openlinkhub.temp.critical' '75')


has_corsairpsu_hwmon() {
  case "${WAYBAR_CORSAIRPSU_PRESENT:-}" in
    0 | false | no) return 1 ;;
    1 | true | yes) return 0 ;;
  esac
  local psu_path_file="$cache_dir/corsairpsu-path.txt" d
  local hwmon_root="${WAYBAR_HWMON_ROOT:-/sys/class/hwmon}"
  if [ -f "$psu_path_file" ]; then
    d=$(cat "$psu_path_file" 2>/dev/null || true)
    if [ -n "$d" ] && [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "corsairpsu" ]; then
      return 0
    fi
  fi
  for d in "$hwmon_root"/hwmon*; do
    if [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "corsairpsu" ]; then
      return 0
    fi
  done
  return 1
}

# Fixture: WAYBAR_OLH_FIXTURE_JSON points at a file with API JSON body.
fixture="${WAYBAR_OLH_FIXTURE_JSON:-}"

if [ -z "$fixture" ]; then
  # Prefer API reachability as source of truth. systemctl can fail in containers
  # / unusual PID namespaces even when the daemon is listening on localhost.
  body=$(curl -sS -m 3 "${api_url}/api/" 2>/dev/null || true)
  if [ -z "$body" ]; then
    if [ "${WAYBAR_OLH_FORCE_ACTIVE:-}" != "1" ] && command -v systemctl >/dev/null 2>&1; then
      if ! systemctl is-active --quiet "$service_name" 2>/dev/null \
        && ! systemctl is-active --quiet openlinkhub 2>/dev/null; then
        emit_disconnected "OpenLinkHub inactive"
      fi
    fi
    emit_disconnected "OpenLinkHub API unreachable ($api_url)"
  fi
else
  body=$(cat "$fixture" 2>/dev/null || true)
fi

if [ -z "$body" ]; then
  emit_disconnected "OpenLinkHub API unreachable ($api_url)"
fi

parsed=$(
  printf '%s' "$body" | jq -c '
    def is_cluster($v):
      (($v.ProductType // 0) == 999)
      or (($v.Product // "" | ascii_downcase) == "cluster")
      or (($v.Serial // "") == "cluster")
      or ($v.Hidden == true and ($v.ProductType // 0) == 999);

    def device_entries:
      if .device then (.device | to_entries)
      elif .devices then
        (if (.devices|type) == "object" then (.devices|to_entries)
         else (.devices | to_entries) end)
      elif .DeviceList then
        (.DeviceList | to_entries)
      else [] end;

    def real_devices:
      [ device_entries[]
        | select(is_cluster(.value) | not)
        | {
            id: .key,
            product: (.value.Product // .value.product // .value.name // .key),
            type: (.value.ProductType // .value.productType // 0),
            is_psu: (
              (.value.GetDevice.IsPSU == true)
              or ((.value.Product // "") | test("HX[0-9]|RM[0-9]|HXi|RMi|PSU"; "i"))
            )
          }
      ];

    # Prefer probe temps > 0; skip nested zeros from idle PSU channels.
    def useful_temps:
      [ (.. | objects
          | (.temperature?, .Temperature?, .psuTemperature?, .vrmTemperature?)
          | select(. != null)
          | select(type == "number" or (type == "string" and test("^[0-9]+(\\.[0-9]+)?$")))
          | tonumber
          | select(. > 0)
        ) ];

    {
      ok: true,
      devices: (real_devices | length),
      names: [real_devices[].product],
      psu_only: ((real_devices | length) > 0 and all(real_devices[]; .is_psu)),
      hot: (useful_temps | if length > 0 then max else null end),
      cpu: (.cpuTemp // .CPUTemp // null),
      gpu: (.gpuTemp // .GPUTemp // null)
    }
  ' 2>/dev/null || true
)

if [ -z "$parsed" ] || ! echo "$parsed" | jq -e '.ok == true' >/dev/null 2>&1; then
  # Non-JSON or unexpected — still show online if HTTP returned something
  write_cache_and_exit "$(emit_waybar_json "󰈐 on" "OpenLinkHub online\nUI: $ui_url\n\nLeft: open UI · Right: restart · Middle: refresh" "normal")"
fi

devices=$(echo "$parsed" | jq -r '.devices // 0')
names=$(echo "$parsed" | jq -r '.names // [] | join(", ")')
psu_only=$(echo "$parsed" | jq -r '.psu_only // false')
hot=$(echo "$parsed" | jq -r '.hot // empty')
cpu_t=$(echo "$parsed" | jq -r '.cpu // empty')
gpu_t=$(echo "$parsed" | jq -r '.gpu // empty')

corsairpsu=0
if has_corsairpsu_hwmon; then
  corsairpsu=1
fi

# Presence-first when configured, or when OLH only mirrors PSU already covered by hwmon.
use_presence=0
if [ "$prefer_presence" = "true" ] || [ "$prefer_presence" = "1" ]; then
  use_presence=1
fi
if [ "$psu_only" = "true" ] && [ "$corsairpsu" -eq 1 ]; then
  use_presence=1
fi

class="normal"
text="󰈐 ${devices}"
if [ "$use_presence" -eq 0 ] && [ -n "$hot" ] && [ "$hot" != "null" ]; then
  hot_i=${hot%.*}
  hot_fmt=$(format_locale_temp "$hot_i" short | tr -d '\n')
  text=$(printf '󰈐 %s' "$hot_fmt")
  if [ "$hot_i" -ge "$temp_crit" ] 2>/dev/null; then
    class="critical"
  elif [ "$hot_i" -ge "$temp_warn" ] 2>/dev/null; then
    class="warning"
  fi
fi

tooltip=$(printf 'OpenLinkHub\nDevices: %s' "$devices")
[ -n "$names" ] && tooltip=$(printf '%s\n  %s' "$tooltip" "$names")
if [ "$corsairpsu" -eq 1 ] && [ "$psu_only" = "true" ]; then
  tooltip=$(printf '%s\nPSU sensors: see PSU module (corsairpsu hwmon)' "$tooltip")
elif [ -n "$hot" ] && [ "$hot" != "null" ]; then
  hot_i=${hot%.*}
  hot_fmt=$(format_locale_temp "$hot_i" short | tr -d '\n')
  tooltip=$(printf '%s\nHottest sensor: %s' "$tooltip" "$hot_fmt")
fi
[ -n "$cpu_t" ] && [ "$cpu_t" != "null" ] && [ "$cpu_t" != "0" ] && tooltip=$(printf '%s\nCPU: %s' "$tooltip" "$cpu_t")
[ -n "$gpu_t" ] && [ "$gpu_t" != "null" ] && [ "$gpu_t" != "0" ] && tooltip=$(printf '%s\nGPU: %s' "$tooltip" "$gpu_t")
tooltip=$(printf '%s\nUI: %s\n\nLeft: open UI · Right: restart · Middle: refresh' "$tooltip" "$ui_url")

write_cache_and_exit "$(emit_waybar_json "$text" "$tooltip" "$class")"
