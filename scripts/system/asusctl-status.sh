#!/usr/bin/env bash
# Waybar status for asusctl / asusd platform profiles (ROG / ASUS laptops).
# Hides (disconnected) when asusctl is missing, asusd is down, or profiles unsupported.
# Optional battery charge-limit line when `asusctl battery info` works.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/asusctl-status.json"
lock_dir="$cache_dir/asusctl-status.lock.d"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
ttl="$(waybar_module_interval asusctl 10)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰓅 --" "Initializing asusctl..." "normal"
  exit 0
fi


resolve_asusctl() {
  if [ -n "${WAYBAR_ASUSCTL_BIN:-}" ]; then
    if [ -x "$WAYBAR_ASUSCTL_BIN" ]; then
      printf '%s' "$WAYBAR_ASUSCTL_BIN"
      return 0
    fi
  fi
  if command -v asusctl >/dev/null 2>&1; then
    command -v asusctl
    return 0
  fi
  for candidate in /usr/bin/asusctl /usr/local/bin/asusctl; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# Normalize Debug/Display profile names from asusctl (e.g. Balanced, "Balanced").
normalize_profile() {
  printf '%s' "$1" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"//; s/"$//'
}

parse_active_profile() {
  # Prefer "Active profile is X" / "Active profile: X"; else last non-empty line.
  local raw="$1" line
  line=$(printf '%s\n' "$raw" | sed -nE 's/.*[Aa]ctive profile is[[:space:]]+(.+)$/\1/p; s/.*[Aa]ctive profile:[[:space:]]*(.+)$/\1/p' | tail -n1)
  if [ -z "$line" ]; then
    line=$(printf '%s\n' "$raw" | sed '/^$/d' | grep -viE 'error|asusd|running|help|usage' | tail -n1 || true)
  fi
  normalize_profile "$line"
}

parse_profile_list() {
  local raw="$1"
  printf '%s\n' "$raw" | sed '/^$/d' | grep -viE 'error|asusd|running|help|usage|available|profiles?:' \
    | while IFS= read -r line; do
      printf '%s\n' "$(normalize_profile "$line")"
    done | awk 'NF' | paste -sd, -
}

parse_battery_limit() {
  local raw="$1"
  printf '%s\n' "$raw" | sed -nE 's/.*[Cc]harge limit:[[:space:]]*([0-9]+)%.*/\1/p; s/.*[[:space:]]([0-9]+)%[[:space:]]*$/\1/p' | head -n1
}

profile_class() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    quiet | power-saver | powersaver) printf 'quiet' ;;
    balanced) printf 'balanced' ;;
    performance | turbo) printf 'performance' ;;
    *) printf 'normal' ;;
  esac
}

profile_icon() {
  case "$(profile_class "$1")" in
    quiet) printf '󰓅' ;;
    balanced) printf '󰾅' ;;
    performance) printf '󱐋' ;;
    *) printf '󰓅' ;;
  esac
}

if ! asusctl_bin="$(resolve_asusctl)"; then
  emit_disconnected "asusctl not installed"
fi

# Allow tests to skip daemon checks.
force_active="${WAYBAR_ASUSCTL_FORCE_ACTIVE:-}"
if [ -z "$force_active" ] && [ -z "${WAYBAR_ASUSCTL_BIN:-}" ]; then
  if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet asusd.service 2>/dev/null \
      && ! systemctl is-active --quiet asusd 2>/dev/null; then
      # Still try CLI — some setups use socket activation; fail soft below.
      :
    fi
  fi
fi

get_out=$("$asusctl_bin" profile get 2>/dev/null || true)
if [ -z "$get_out" ]; then
  # Older CLI flags
  get_out=$("$asusctl_bin" profile --profile-get 2>/dev/null || true)
fi

# Daemon missing / unsupported → hide
if printf '%s' "$get_out" | grep -qiE 'asusd is not running|not supported|ServiceUnknown|Could not get'; then
  emit_disconnected "asusd not running or profiles unsupported"
fi

current=$(parse_active_profile "$get_out")
if [ -z "$current" ]; then
  emit_disconnected "asusctl profile unavailable"
fi

list_out=$("$asusctl_bin" profile list 2>/dev/null || true)
if [ -z "$list_out" ]; then
  list_out=$("$asusctl_bin" profile --list 2>/dev/null || true)
fi
profiles_csv=$(parse_profile_list "$list_out")

batt_out=$("$asusctl_bin" battery info 2>/dev/null || true)
batt_limit=$(parse_battery_limit "$batt_out")

class=$(profile_class "$current")
icon=$(profile_icon "$current")
# Compact bar text: icon + short name
short="$current"
case "$(printf '%s' "$current" | tr '[:upper:]' '[:lower:]')" in
  quiet) short="Quiet" ;;
  balanced) short="Bal" ;;
  performance) short="Perf" ;;
esac
text=$(printf '%s %s' "$icon" "$short")

tooltip_lines=("ASUS profile" "" "Active: $current")
if [ -n "$profiles_csv" ]; then
  tooltip_lines+=("Available: ${profiles_csv//,/, }")
fi
if [ -n "$batt_limit" ]; then
  tooltip_lines+=("Charge limit: ${batt_limit}%")
fi
tooltip_lines+=("" "Scroll / click: cycle or pick profile")

tooltip=$(printf '%s\n' "${tooltip_lines[@]}")
esc_text=$(escape_markup "$text")
esc_tooltip=$(escape_markup "$tooltip")
write_cache_and_exit "$(jq -cn \
  --arg text "$esc_text" \
  --arg tooltip "$esc_tooltip" \
  --arg class "$class" \
  --arg profile "$current" \
  '{text:$text, tooltip:$tooltip, class:$class, alt:$profile}')"
