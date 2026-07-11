#!/usr/bin/env bash
# Cached UPS status (one NUT/UPower probe per TTL across all Waybar instances).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(dirname "$0")"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

ups_warn=$(waybar_settings_get '.thresholds.ups.charge.warning' '25')
ups_crit=$(waybar_settings_get '.thresholds.ups.charge.critical' '10')

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
slug="$(printf '%s' "${NUT_TARGET:-auto}" | tr -c 'A-Za-z0-9._-' '_' | head -c 120)"
[ -z "$slug" ] && slug="auto"
cache_file="$cache_dir/ups-status.${slug}.json"
lock_dir="$cache_dir/ups-status.${slug}.lock.d"
ttl="$(waybar_module_interval ups 30)"
stale_lock_ttl=45

mkdir -p "$cache_dir"


format_runtime() {
  raw="$1"

  case "$raw" in
    '' | *[!0-9]*)
      printf '%s' "$raw"
      return
      ;;
  esac

  if [ "$raw" -lt 60 ]; then
    printf '%ss' "$raw"
    return
  fi

  if [ "$raw" -lt 3600 ]; then
    m=$((raw / 60))
    s=$((raw % 60))
    if [ "$s" -eq 0 ]; then
      printf '%sm' "$m"
    else
      printf '%sm %ss' "$m" "$s"
    fi
    return
  fi

  if [ "$raw" -lt 86400 ]; then
    h=$((raw / 3600))
    m=$(((raw % 3600) / 60))
    if [ "$m" -eq 0 ]; then
      printf '%sh' "$h"
    else
      printf '%sh %sm' "$h" "$m"
    fi
    return
  fi

  d=$((raw / 86400))
  h=$(((raw % 86400) / 3600))
  if [ "$h" -eq 0 ]; then
    printf '%sd' "$d"
  else
    printf '%sd %sh' "$d" "$h"
  fi
}

upsc_list=""
if command -v upsc >/dev/null 2>&1; then
  upsc_list=$(timeout 2 upsc -l 127.0.0.1 2>/dev/null || true)
fi

# nut_target_candidates:
# Generates a list of potential NUT targets to try.
# It deduplicates names and tries to read the default or custom NUT daemon targets.
nut_target_candidates() {
  seen=""
  add_candidate() {
    candidate="$1"
    [ -n "$candidate" ] || return 0
    case "$seen" in
      *"|$candidate|"*) return 0 ;;
    esac
    seen="${seen}|${candidate}|"
    printf '%s\n' "$candidate"
  }

  add_candidate "${NUT_TARGET:-}"
  add_candidate "ups@127.0.0.1"
  add_candidate "ups@127.0.0.1:3493"

  if [ -n "$upsc_list" ]; then
    nut_name=$(printf '%s\n' "$upsc_list" | awk 'NR==1 {print; exit}')
    if [ -n "$nut_name" ]; then
      add_candidate "${nut_name}@127.0.0.1"
      add_candidate "${nut_name}@127.0.0.1:3493"
    fi
  fi
}

# json_from_nut_info:
# Parses standard NUT get/upsc outputs and packages them into Waybar-compatible JSON.
# Handles online, charging, and discharging classes and states.
json_from_nut_info() {
  nut_target="$1"
  nut_info="$2"

  pct=$(printf '%s\n' "$nut_info" | awk -F': *' '/^battery\.charge:/ {print $2; exit}')
  st=$(printf '%s\n' "$nut_info" | awk -F': *' '/^ups\.status:/ {print $2; exit}')
  runtime=$(printf '%s\n' "$nut_info" | awk -F': *' '/^battery\.runtime:/ {print $2; exit}')

  text="󰁹"
  is_discharging=0
  case "${st:-}" in
    *DISCHRG*)
      text="󰂃"
      is_discharging=1
      ;;
    *CHRG*)
      text="󰂄"
      ;;
  esac

  num=$(printf '%s' "$pct" | tr -dc '0-9')
  if [ -n "$num" ]; then
    text="${text} $(printf '%3d' "$num")%"
  fi

  cls="good"
  if [ -n "$num" ] && [ "$num" -le "$ups_crit" ]; then
    cls="critical"
  elif [ -n "$num" ] && [ "$num" -le "$ups_warn" ]; then
    cls="warning"
  elif [ "$is_discharging" -eq 1 ]; then
    cls="warning"
  fi

  tip=$(printf 'Target: %s\nCharge: %s%%\nStatus: %s' "$nut_target" "${pct:-?}" "${st:-unknown}")
  if [ -n "${runtime:-}" ]; then
    tip=$(printf '%s\nRuntime: %s' "$tip" "$(format_runtime "$runtime")")
  fi
  tip=$(printf '%s\n\nLeft: power settings · Right: system monitor · Middle: refresh' "$tip")

  emit_waybar_json "$text" "$tip" "$cls"
}

# find_upower_ups_device:
# Scans for an uninterruptible power supply registered via UPower.
# Useful for USB-connected UPS devices that report directly to systemd-upowerd.
find_upower_ups_device() {
  if ! command -v upower >/dev/null 2>&1; then
    return 1
  fi

  dev=$(timeout 2 upower -e 2>/dev/null | awk 'tolower($0) ~ /ups|uninterruptible/ {print; exit}' || true)
  [ -n "$dev" ] || return 1
  printf '%s' "$dev"
}

# collect_json:
# Main orchestrator for UPS state discovery.
# Tries NUT (via local/remote daemons) first, then falls back to local UPower.
collect_json() {
  nut_listed=""
  if [ -n "$upsc_list" ]; then
    nut_listed=$(printf '%s\n' "$upsc_list" | awk 'NF {print; exit}')
  fi

  if command -v upsc >/dev/null 2>&1; then
    while IFS= read -r nut_target; do
      [ -n "$nut_target" ] || continue
      nut_info=$(timeout 2 upsc "$nut_target" 2>/dev/null || true)
      if [ -n "$nut_info" ]; then
        json_from_nut_info "$nut_target" "$nut_info"
        return 0
      fi
    done <<EOF
$(nut_target_candidates)
EOF
  fi

  if [ -n "$nut_listed" ]; then
    emit_waybar_json "󰂄 …" "NUT UPS '${nut_listed}' is registered but the driver is not connected yet. Check nut-driver / upsdrvctl." "warning"
    return 0
  fi

  dev=$(find_upower_ups_device || true)
  if [ -z "$dev" ]; then
    emit_waybar_json "󰂑 N/A" "No UPS detected (NUT/UPower)" "disconnected"
    return 0
  fi

  info=$(timeout 2 upower -i "$dev" 2>/dev/null || true)
  st=$(printf '%s\n' "$info" | awk -F: '/state/ {gsub(/^ +/, "", $2); print $2; exit}')
  pct=$(printf '%s\n' "$info" | awk -F: '/percentage/ {gsub(/^ +/, "", $2); print $2; exit}')

  text="󰁹"
  [ "$st" = "charging" ] && text="󰂄"
  [ "$st" = "discharging" ] && text="󰂃"

  num=$(printf '%s' "$pct" | tr -dc '0-9')
  if [ -n "$num" ]; then
    text="${text} $(printf '%3d' "$num")%"
  fi

  cls="good"
  if [ -n "$num" ] && [ "$num" -le "$ups_crit" ]; then
    cls="critical"
  elif [ -n "$num" ] && [ "$num" -le "$ups_warn" ]; then
    cls="warning"
  elif [ "$st" = "discharging" ]; then
    cls="warning"
  fi

  tip=$(printf 'Device: %s\nCharge: %s\nState: %s\n\nLeft: power settings · Right: system monitor · Middle: refresh' "$dev" "${pct:-?}" "${st:-unknown}")
  emit_waybar_json "$text" "$tip" "$cls"
}

if [ "${1:-}" != "--refresh" ]; then
  # Self-adaptive TTL: if no UPS was detected, cache this state for 10 minutes (600s)
  # to avoid executing upsc/upower background queries on machines without UPS hardware.
  if [ -f "$cache_file" ]; then
    if grep -q '"class":"disconnected"' "$cache_file"; then
      ttl=600
    fi
  fi

  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi

  emit_waybar_json "󰦌" "Refreshing UPS status in background" "disabled"
  exit 0
fi

json="$(collect_json)"
printf '%s\n' "$json"

tmp="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp"
mv -f "$tmp" "$cache_file"
