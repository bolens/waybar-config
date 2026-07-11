#!/usr/bin/env bash
# Waybar status for liquidctl devices (AIO coolers, USB PSUs, fan hubs, …).
# Bar prefers liquid temp → other temps → pump RPM → fan RPM → power.
# Hides (disconnected) when liquidctl is missing or no useful telemetry is available.
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

# --refresh mode
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
temp_warn=$(waybar_settings_get '.thresholds.liquidctl.temp.warning' '55')
temp_crit=$(waybar_settings_get '.thresholds.liquidctl.temp.critical' '65')
match=$(waybar_settings_get '.liquidctl.match' '')
pick=$(waybar_settings_get '.liquidctl.pick' '')

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
    # Stale override (e.g. deleted test fixture) — fall through to real lookup.
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

if ! liquidctl_bin="$(resolve_liquidctl)"; then
  emit_disconnected "liquidctl not installed"
fi

# liquidctl omits --json output when *any* device errors (common with Aura LED).
# Prefer a bulk status call; on empty/fail, probe each listed device with --pick.
fetch_liquidctl_status_json() {
  local bulk ec=0 chunk status_merged="[]" i count driver desc list_json
  local -a bulk_cmd probe_cmd list_cmd

  bulk_cmd=(timeout 4 "$liquidctl_bin" status --json)
  if [ -n "$match" ] && [ "$match" != "null" ]; then
    bulk_cmd+=(--match "$match")
  fi
  if [ -n "$pick" ] && [ "$pick" != "null" ]; then
    bulk_cmd+=(--pick "$pick")
  fi

  bulk="$("${bulk_cmd[@]}" 2>/dev/null)" || ec=$?
  if [ -n "$bulk" ]; then
    printf '%s' "$bulk"
    return 0
  fi

  # Explicit pick already failed — nothing left to try.
  if [ -n "$pick" ] && [ "$pick" != "null" ]; then
    return 1
  fi

  list_cmd=(timeout 4 "$liquidctl_bin" list --json)
  if [ -n "$match" ] && [ "$match" != "null" ]; then
    list_cmd+=(--match "$match")
  fi
  list_json="$("${list_cmd[@]}" 2>/dev/null)" || true
  if [ -z "$list_json" ]; then
    return 1
  fi

  count="$(printf '%s' "$list_json" | jq 'length')"
  i=0
  while [ "$i" -lt "${count:-0}" ]; do
    # Skip known RGB-only drivers that often error and add no telemetry.
    driver="$(printf '%s' "$list_json" | jq -r --argjson i "$i" '.[$i].driver // ""')"
    desc="$(printf '%s' "$list_json" | jq -r --argjson i "$i" '.[$i].description // ""')"
    case "$driver" in
      AuraLed|AuraLedController)
        i=$((i + 1))
        continue
        ;;
    esac
    if printf '%s' "$desc" | grep -qi 'Aura LED'; then
      i=$((i + 1))
      continue
    fi

    probe_cmd=(timeout 4 "$liquidctl_bin" status --json --pick "$i")
    if [ -n "$match" ] && [ "$match" != "null" ]; then
      probe_cmd+=(--match "$match")
    fi
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

# Parse devices with useful telemetry (temps / rpm / power / current / voltage).
# Skip RGB-only / empty status devices.
parsed="$(printf '%s' "$status_raw" | jq -c '
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

  [ .[]?
    | . as $dev
    | ($dev.status // []) as $st
    | ($st | map(select(useful(.unit; .key)))) as $useful
    | select(($useful | length) > 0)
    | {
        description: ($dev.description // "device"),
        status: $useful,
        primary: (
          $useful
          | sort_by(rank_key(.key))
          | .[0]
        )
      }
  ]
')"

device_count="$(printf '%s' "$parsed" | jq 'length')"
if [ "${device_count:-0}" -eq 0 ]; then
  emit_disconnected "liquidctl: no telemetry devices"
fi

# Primary bar metric: best-ranked reading across devices.
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

# Max °C across useful readings for threshold class.
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

# Format bar text
text="󰖌 --"
case "$punit" in
  °C|C)
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

# Tooltip: one block per device
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

# status_ec is informational once JSON parsed successfully
: "${status_ec:=0}"

json=$(emit_waybar_json "$text" "$tooltip" "$class")
write_cache_and_exit "$json"
