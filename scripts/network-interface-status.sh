#!/usr/bin/env sh
# Waybar status for eno1, enp5s0, and wlan0 — hidden while bond0 is active.
set -eu

if [ "${1:-}" = "--refresh" ]; then
  _refresh_only=1
  shift
fi

iface="${1:-}"
if [ -z "$iface" ] && [ "${_refresh_only:-0}" != "1" ]; then
  printf '{"text":"","tooltip":"network-interface-status: missing interface","class":"hidden"}\n'
  exit 0
fi

script_dir="${0%/*}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$script_dir/waybar-cache-helpers.sh"

cache_file="$cache_dir/network-interfaces-status.json"
lock_dir="$cache_dir/network-interfaces-status.lock.d"
ttl=15
stale_lock_ttl=30

mkdir -p "$cache_dir"

bond_is_active() {
  [ -d /sys/class/net/bond0 ] || return 1
  operstate="$(cat /sys/class/net/bond0/operstate 2>/dev/null || printf 'down')"
  [ "$operstate" = "up" ] || return 1

  if command -v nmcli >/dev/null 2>&1; then
    nm_state="$(timeout 2 nmcli -t -f DEVICE,STATE device status 2>/dev/null \
      | awk -F: '$1=="bond0"{print $2; exit}' || true)"
    case "$nm_state" in
      connected|connecting) return 0 ;;
      disconnected|unavailable|unmanaged) return 1 ;;
    esac
  fi

  return 0
}

iface_kind() {
  case "$1" in
    wlan*|wlp*|wl*) printf 'wifi' ;;
    *) printf 'ethernet' ;;
  esac
}

ipv4_for_iface() {
  dev="$1"
  ip -4 -o addr show dev "$dev" scope global 2>/dev/null \
    | awk 'NR==1 {split($4, parts, "/"); printf "%s/%s", parts[1], parts[2]; exit}'
}

operstate_for_iface() {
  dev="$1"
  [ -f "/sys/class/net/$dev/operstate" ] || { printf 'down'; return; }
  cat "/sys/class/net/$dev/operstate" 2>/dev/null || printf 'down'
}

wifi_essid() {
  dev="$1"
  essid=''
  if command -v iwgetid >/dev/null 2>&1; then
    essid="$(iwgetid -r "$dev" 2>/dev/null || true)"
  fi
  if [ -z "$essid" ] && command -v nmcli >/dev/null 2>&1; then
    essid="$(timeout 2 nmcli -t -f GENERAL.CONNECTION dev show "$dev" 2>/dev/null \
      | awk -F: 'NR==1 {print $2; exit}' || true)"
    [ "$essid" = "--" ] && essid=''
  fi
  printf '%s' "$essid"
}

wifi_signal_pct() {
  dev="$1"
  [ -r /proc/net/wireless ] || { printf ''; return; }
  awk -v iface="$dev" '
    $1 ~ iface":" {
      gsub(/\./, "", $4)
      q = int($3)
      if (q > 70) q = 70
      if (q < 0) q = 0
      printf "%d", int((q / 70) * 100)
      exit
    }
  ' /proc/net/wireless 2>/dev/null || true
}

build_iface_json() {
  dev="$1"
  kind="$(iface_kind "$dev")"
  bond_active="$2"

  if [ "$bond_active" = "1" ]; then
    jq -cn \
      --arg class "hidden $dev" \
      '{text:"", tooltip:"", class:$class}'
    return
  fi

  operstate="$(operstate_for_iface "$dev")"
  ipv4="$(ipv4_for_iface "$dev")"

  if [ "$kind" = "wifi" ]; then
    essid="$(wifi_essid "$dev")"
    signal="$(wifi_signal_pct "$dev")"

    if [ "$operstate" = "up" ] && [ -n "$essid" ]; then
      text='󰤨'
      class='connected'
      if [ -n "$ipv4" ] && [ -n "$signal" ]; then
        tooltip=$(printf '%s (%s%%)\n%s: %s' "$essid" "$signal" "$dev" "$ipv4")
      elif [ -n "$ipv4" ]; then
        tooltip=$(printf '%s\n%s: %s' "$essid" "$dev" "$ipv4")
      elif [ -n "$signal" ]; then
        tooltip=$(printf '%s (%s%%)\n%s: link up (no IPv4)' "$essid" "$signal" "$dev")
      else
        tooltip=$(printf '%s\n%s: link up (no IPv4)' "$essid" "$dev")
      fi
    elif [ "$operstate" = "up" ]; then
      text='󰤨'
      class='connected'
      if [ -n "$ipv4" ]; then
        tooltip=$(printf '%s\n%s: %s' "$dev" "$dev" "$ipv4")
      else
        tooltip=$(printf '%s\n%s: link up (no IPv4)' "$dev" "$dev")
      fi
    else
      text='󰤭'
      class='disconnected'
      tooltip=$(printf 'OFF\n%s' "$dev")
    fi
  else
    if [ "$operstate" = "up" ] && [ -n "$ipv4" ]; then
      text='󰈀'
      class='connected'
      tooltip="${dev}: ${ipv4}"
    elif [ "$operstate" = "up" ]; then
      text='󰈀'
      class='connected'
      tooltip="${dev}: link up (no IPv4)"
    else
      text='󰈁'
      class='disconnected'
      tooltip=$(printf 'Disconnected\n%s' "$dev")
    fi
  fi

  jq -cn \
    --arg text "$text" \
    --arg tooltip "$tooltip" \
    --arg class "$class $dev" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

refresh_cache() {
  bond_active=0
  if bond_is_active; then
    bond_active=1
  fi

  eno1_json="$(build_iface_json eno1 "$bond_active")"
  enp5s0_json="$(build_iface_json enp5s0 "$bond_active")"
  wlan0_json="$(build_iface_json wlan0 "$bond_active")"

  jq -cn \
    --argjson bond_active "$bond_active" \
    --argjson eno1 "$eno1_json" \
    --argjson enp5s0 "$enp5s0_json" \
    --argjson wlan0 "$wlan0_json" \
    --arg updated "$(date +%s)" \
    '{bond_active:$bond_active, eno1:$eno1, enp5s0:$enp5s0, wlan0:$wlan0, updated:$updated}'
}


if [ "${_refresh_only:-0}" = "1" ]; then
  json="$(refresh_cache)"
  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" > "$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
  exit 0
fi

age="$(cache_file_age "$cache_file")"
if [ "$age" -le "$ttl" ] 2>/dev/null && [ -f "$cache_file" ]; then
  jq -c --arg iface "$iface" '.[$iface] // {text:"", tooltip:"", class:"hidden"}' "$cache_file"
  exit 0
fi

cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"

if [ -f "$cache_file" ]; then
  [ -d "$lock_dir" ] || refresh_in_background
  jq -c --arg iface "$iface" '.[$iface] // {text:"", tooltip:"", class:"hidden"}' "$cache_file"
  exit 0
fi

[ -d "$lock_dir" ] || refresh_in_background
bond_active=0
bond_is_active && bond_active=1
build_iface_json "$iface" "$bond_active"
