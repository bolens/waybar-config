#!/usr/bin/env bash
# Waybar status for liquidctl devices (AIO coolers, fan hubs, …).
# Prefers liquidctl for devices NOT already covered by cheaper sources:
#   - CorsairHidPsu skipped when corsairpsu hwmon exists (custom/psu)
#   - Aura RGB skipped (use OpenRGB/ckb-next)
# Hides when nothing useful remains (avoids HID probes for covered devices).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/liquidctl-status.json"
lock_dir="$cache_dir/liquidctl-status.lock.d"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
ttl="$(waybar_module_interval liquidctl 10)"
stale_lock_ttl=15

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰖌 --" "Initializing liquidctl..." "normal"
  exit 0
fi

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
temp_warn=$(waybar_settings_get '.thresholds.liquidctl.temp.warning' '55')
temp_crit=$(waybar_settings_get '.thresholds.liquidctl.temp.critical' '65')
match=$(waybar_settings_get '.liquidctl.match' '')
pick=$(waybar_settings_get '.liquidctl.pick' '')
skip_psu=$(waybar_settings_get '.liquidctl.skip_corsair_psu_if_hwmon' 'true')

write_cache_and_exit() {
  json="$1"
  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  if printf '%s\n' "$json" >"$tmp_cache" 2>/dev/null; then
    mv -f "$tmp_cache" "$cache_file" 2>/dev/null || rm -f "$tmp_cache" 2>/dev/null || true
  fi
  exit 0
}

emit_disconnected() {
  write_cache_and_exit "$(emit_waybar_json "" "$1" "disconnected")"
}

resolve_liquidctl() {
  if [ -n "${WAYBAR_LIQUIDCTL_BIN:-}" ]; then
    if [ -x "$WAYBAR_LIQUIDCTL_BIN" ]; then
      printf '%s' "$WAYBAR_LIQUIDCTL_BIN"
      return 0
    fi
  fi
  if command -v liquidctl >/dev/null 2>&1; then
    command -v liquidctl
    return 0
  fi
  for candidate in \
    "$HOME/.local/bin/liquidctl" \
    /usr/bin/liquidctl \
    /usr/local/bin/liquidctl; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

has_corsairpsu_hwmon() {
  # Test overrides: WAYBAR_CORSAIRPSU_PRESENT=0|1
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
      printf '%s\n' "$d" >"$psu_path_file.tmp.$$" 2>/dev/null \
        && mv -f "$psu_path_file.tmp.$$" "$psu_path_file" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

is_rgb_only() {
  local driver="$1" desc="$2"
  case "$driver" in
    AuraLed | AuraLedController) return 0 ;;
  esac
  printf '%s' "$desc" | grep -qi 'Aura LED' && return 0
  return 1
}

is_corsair_psu_driver() {
  local driver="$1" desc="$2"
  case "$driver" in
    CorsairHidPsu | CorsairPsu) return 0 ;;
  esac
  printf '%s' "$desc" | grep -qiE 'HX[0-9]|RM[0-9]|HXi|RMi|Corsair.*(PSU|Power Supply)' && return 0
  return 1
}

should_skip_device() {
  local driver="$1" desc="$2"
  if is_rgb_only "$driver" "$desc"; then
    return 0
  fi
  if [ "$skip_psu_hwmon" -eq 1 ] && is_corsair_psu_driver "$driver" "$desc"; then
    return 0
  fi
  return 1
}

if ! liquidctl_bin="$(resolve_liquidctl)"; then
  emit_disconnected "liquidctl not installed"
fi

skip_psu_hwmon=0
if [ "$skip_psu" = "true" ] || [ "$skip_psu" = "1" ]; then
  if has_corsairpsu_hwmon; then
    skip_psu_hwmon=1
  fi
fi

# One list call: decide whether any device still needs liquidctl (avoid status/HID when PSU-only).
list_json=""
list_cmd=(timeout 4 "$liquidctl_bin" list --json)
if [ -n "$match" ] && [ "$match" != "null" ]; then
  list_cmd+=(--match "$match")
fi
list_json="$("${list_cmd[@]}" 2>/dev/null)" || true

keep_count=0
aura_n=0
skipped_psu_n=0
if [ -n "$list_json" ]; then
  count="$(printf '%s' "$list_json" | jq 'length' 2>/dev/null || echo 0)"
  i=0
  while [ "$i" -lt "${count:-0}" ]; do
    driver="$(printf '%s' "$list_json" | jq -r --argjson i "$i" '.[$i].driver // ""')"
    desc="$(printf '%s' "$list_json" | jq -r --argjson i "$i" '.[$i].description // ""')"
    if is_rgb_only "$driver" "$desc"; then
      aura_n=$((aura_n + 1))
    elif [ "$skip_psu_hwmon" -eq 1 ] && is_corsair_psu_driver "$driver" "$desc"; then
      skipped_psu_n=$((skipped_psu_n + 1))
    else
      keep_count=$((keep_count + 1))
    fi
    i=$((i + 1))
  done
fi

if [ "$keep_count" -eq 0 ]; then
  reason="liquidctl: no exclusive devices"
  if [ "$skipped_psu_n" -gt 0 ]; then
    reason="liquidctl: PSU covered by corsairpsu hwmon (see PSU module)"
  elif [ "$aura_n" -gt 0 ]; then
    reason="liquidctl: only Aura RGB (use OpenRGB/ckb-next)"
  fi
  emit_disconnected "$reason"
fi

# Fetch status only for devices liquidctl still owns (never bulk when skips apply —
# bulk still talks HID to PSU/Aura and races OpenLinkHub / corsairpsu).
fetch_liquidctl_status_json() {
  local bulk chunk status_merged="[]" i count driver desc
  local -a bulk_cmd probe_cmd
  local skipped_any=0

  # Explicit pick / match: honor user override (they asked for that device).
  if { [ -n "$pick" ] && [ "$pick" != "null" ]; } || { [ -n "$match" ] && [ "$match" != "null" ]; }; then
    bulk_cmd=(timeout 4 "$liquidctl_bin" status --json)
    [ -n "$match" ] && [ "$match" != "null" ] && bulk_cmd+=(--match "$match")
    [ -n "$pick" ] && [ "$pick" != "null" ] && bulk_cmd+=(--pick "$pick")
    bulk="$("${bulk_cmd[@]}" 2>/dev/null)" || true
    printf '%s' "$bulk"
    [ -n "$bulk" ]
    return $?
  fi

  if [ "$aura_n" -gt 0 ] || [ "$skipped_psu_n" -gt 0 ]; then
    skipped_any=1
  fi

  # Only bulk when every listed device is a keeper (no wasted HID).
  if [ "$skipped_any" -eq 0 ]; then
    bulk_cmd=(timeout 4 "$liquidctl_bin" status --json)
    bulk="$("${bulk_cmd[@]}" 2>/dev/null)" || true
    if [ -n "$bulk" ]; then
      printf '%s' "$bulk"
      return 0
    fi
  fi

  # Per-device probe for keepers only (Aura/PSU skipped).
  count="$(printf '%s' "$list_json" | jq 'length')"
  i=0
  while [ "$i" -lt "${count:-0}" ]; do
    driver="$(printf '%s' "$list_json" | jq -r --argjson i "$i" '.[$i].driver // ""')"
    desc="$(printf '%s' "$list_json" | jq -r --argjson i "$i" '.[$i].description // ""')"
    if should_skip_device "$driver" "$desc"; then
      i=$((i + 1))
      continue
    fi
    probe_cmd=(timeout 4 "$liquidctl_bin" status --json --pick "$i")
    chunk="$("${probe_cmd[@]}" 2>/dev/null)" || true
    if [ -n "$chunk" ]; then
      status_merged="$(jq -c -s 'add' <(printf '%s' "$status_merged") <(printf '%s' "$chunk") 2>/dev/null || printf '%s' "$status_merged")"
    fi
    i=$((i + 1))
  done

  if [ "$status_merged" = "[]" ] || [ -z "$status_merged" ]; then
    return 1
  fi
  printf '%s' "$status_merged"
  return 0
}

status_raw=""
status_ec=0
status_raw="$(fetch_liquidctl_status_json)" || status_ec=$?

if [ -z "$status_raw" ]; then
  emit_disconnected "liquidctl: no status (permissions or no device)"
fi

# Drop devices already covered / RGB-only from the status payload.
parsed="$(printf '%s' "$status_raw" | jq -c --argjson skip_psu "$skip_psu_hwmon" '
  def useful($u; $k):
    ($u == "°C" or $u == "C" or $u == "rpm" or $u == "W" or $u == "V" or $u == "A" or $u == "%")
    or ($k | test("temperature|speed|power|voltage|current|duty|pump|fan|liquid"; "i"));

  def rank_key($k):
    if ($k | test("^Liquid temperature$"; "i")) then 0
    elif ($k | test("liquid"; "i") and test("temp"; "i")) then 1
    elif ($k | test("VRM temperature"; "i")) then 2
    elif ($k | test("temperature"; "i")) then 3
    elif ($k | test("^Pump speed$"; "i")) then 10
    elif ($k | test("pump"; "i") and test("speed|duty"; "i")) then 11
    elif ($k | test("fan"; "i") and test("speed|duty"; "i")) then 20
    elif ($k | test("Total power output"; "i")) then 30
    elif ($k | test("power"; "i")) then 31
    else 100 end;

  def skip_dev:
    ((.driver // "") | test("Aura|CorsairHidPsu|CorsairPsu"; "i"))
    or ((.description // "") | test("Aura LED"; "i"))
    or ($skip_psu == 1 and ((.description // "") | test("HX[0-9]|RM[0-9]|HXi|RMi|Corsair.*(PSU|Power Supply)"; "i")));

  [ .[]?
    | select(skip_dev | not)
    | . as $dev
    | ($dev.status // []) as $st
    | ($st | map(select(useful(.unit; .key)))) as $useful
    | select(($useful | length) > 0)
    | {
        description: ($dev.description // "device"),
        status: $useful,
        primary: ($useful | sort_by(rank_key(.key)) | .[0])
      }
  ]
')"

device_count="$(printf '%s' "$parsed" | jq 'length')"
if [ "${device_count:-0}" -eq 0 ]; then
  emit_disconnected "liquidctl: covered by hwmon/OpenLinkHub/RGB tools"
fi

primary="$(printf '%s' "$parsed" | jq -c '
  def rank_key($k):
    if ($k | test("^Liquid temperature$"; "i")) then 0
    elif ($k | test("liquid"; "i") and test("temp"; "i")) then 1
    elif ($k | test("VRM temperature"; "i")) then 2
    elif ($k | test("temperature"; "i")) then 3
    elif ($k | test("^Pump speed$"; "i")) then 10
    elif ($k | test("pump"; "i") and test("speed|duty"; "i")) then 11
    elif ($k | test("fan"; "i") and test("speed|duty"; "i")) then 20
    elif ($k | test("Total power output"; "i")) then 30
    elif ($k | test("power"; "i")) then 31
    else 100 end;
  map({description, primary}) | sort_by(rank_key(.primary.key)) | .[0]
')"

pkey="$(printf '%s' "$primary" | jq -r '.primary.key')"
pvalue="$(printf '%s' "$primary" | jq -r '.primary.value')"
punit="$(printf '%s' "$primary" | jq -r '.primary.unit')"
pdesc="$(printf '%s' "$primary" | jq -r '.description')"

max_temp="$(printf '%s' "$parsed" | jq -r '
  [ .[].status[] | select(.unit == "°C" or .unit == "C") | (.value | tonumber? // empty) ]
  | if length == 0 then empty else max end
')"

class="normal"
if [ -n "${max_temp:-}" ]; then
  temp_int="${max_temp%.*}"
  if [ -n "$temp_int" ] && [ "$temp_int" -ge "$temp_crit" ] 2>/dev/null; then
    class="critical"
  elif [ -n "$temp_int" ] && [ "$temp_int" -ge "$temp_warn" ] 2>/dev/null; then
    class="warning"
  fi
fi

text="󰖌 --"
case "$punit" in
  °C | C)
    temp_int="${pvalue%.*}"
    if [ -n "$temp_int" ]; then
      temp_fmt=$(format_locale_temp "$temp_int" short | tr -d '\n')
      text=$(printf '󰖌 %s' "$temp_fmt")
    fi
    ;;
  rpm)
    rpm_int="${pvalue%.*}"
    text=$(printf '󰖌 %s RPM' "${rpm_int:-$pvalue}")
    ;;
  W)
    watts="${pvalue%.*}"
    text=$(printf '󰖌 %sW' "${watts:-$pvalue}")
    ;;
  %)
    pct="${pvalue%.*}"
    text=$(printf '󰖌 %s%%' "${pct:-$pvalue}")
    ;;
  *)
    text=$(printf '󰖌 %s %s' "$pvalue" "$punit")
    ;;
esac

tooltip="$(printf '%s' "$parsed" | jq -r --arg bar_hint "$pdesc · $pkey" --argjson multi "$device_count" '
  def fmt($v; $u):
    if ($v | type) == "number" then
      if $u == "°C" or $u == "C" or $u == "W" or $u == "V" or $u == "A" then
        "\($v | tonumber | . * 10 | round / 10) \($u)"
      elif $u == "rpm" then
        "\($v | tonumber | floor) RPM"
      elif $u == "%" then
        "\($v | tonumber | floor)%"
      else
        "\($v) \($u)"
      end
    else
      "\($v) \($u)"
    end;
  [
    "liquidctl",
    (if $multi > 1 then "Bar: \($bar_hint)" else empty end),
    (map(
      .description as $d
      | (.status | length) as $n
      | .status
      | to_entries
      | map(
          (if .key == ($n - 1) then "  └─ " else "  ├─ " end)
          + .value.key + ": " + fmt(.value.value; .value.unit)
        )
      | "\($d)\n\(join("\n"))"
    ) | join("\n")),
    "",
    "Left: btop · Right: system monitor · Middle: refresh"
  ] | map(select(. != null and . != "")) | join("\n")
')"

notes=()
if [ "$skipped_psu_n" -gt 0 ]; then
  notes+=("Skipped $skipped_psu_n Corsair PSU (corsairpsu hwmon / PSU module)")
fi
if [ "$aura_n" -gt 0 ]; then
  notes+=("Skipped $aura_n Aura RGB device(s) (use OpenRGB/ckb-next)")
fi
for n in "${notes[@]}"; do
  tooltip=$(printf '%s\n%s' "$tooltip" "$n")
done

: "${status_ec:=0}"
write_cache_and_exit "$(emit_waybar_json "$text" "$tooltip" "$class")"
