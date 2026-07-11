#!/usr/bin/env bash
# Waybar status for RGB stacks (OpenRGB / ckb-next).
# Shows only when a daemon is running; otherwise disconnected (hidden).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/rgb-status.json"
lock_dir="$cache_dir/rgb-status.lock.d"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
ttl="$(waybar_module_interval rgb 10)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰃠 --" "Initializing RGB..." "normal"
  exit 0
fi

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

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

openrgb_bin="${WAYBAR_OPENRGB_BIN:-}"
if [ -z "$openrgb_bin" ] && command -v openrgb >/dev/null 2>&1; then
  openrgb_bin=$(command -v openrgb)
fi

ckb_running=0
openrgb_running=0
openrgb_devices=""
lines=()

if [ "${WAYBAR_RGB_FORCE_IDLE:-0}" = "1" ]; then
  emit_disconnected "RGB forced idle (test)"
fi

# ckb-next daemon
if [ "${WAYBAR_RGB_FORCE_CKB:-0}" = "1" ] || pgrep -x ckb-next >/dev/null 2>&1 || pgrep -f 'ckb-next-daemon|ckb-next --' >/dev/null 2>&1; then
  if [ "${WAYBAR_RGB_FORCE_IDLE:-0}" != "1" ]; then
    ckb_running=1
    lines+=("ckb-next: running")
  fi
fi

# OpenRGB: prefer daemon / SDK server; fall back to listing devices if CLI works quickly
if [ "${WAYBAR_RGB_FORCE_OPENRGB:-0}" = "1" ] || pgrep -x openrgb >/dev/null 2>&1 || pgrep -f 'openrgb --server|openrgb --mode' >/dev/null 2>&1; then
  if [ "${WAYBAR_RGB_FORCE_IDLE:-0}" != "1" ]; then
    openrgb_running=1
  fi
fi

if [ -n "$openrgb_bin" ] && [ -x "$openrgb_bin" ] && [ "${WAYBAR_RGB_FORCE_IDLE:-0}" != "1" ]; then
  list_out=$(timeout 2 "$openrgb_bin" --list-devices 2>/dev/null || true)
  if [ -n "$list_out" ]; then
    openrgb_running=1
    count=$(printf '%s\n' "$list_out" | grep -cE '^[0-9]+:' || true)
    openrgb_devices="$count"
    lines+=("OpenRGB: ${count} device(s)")
    # Sample first few device names
    names=$(printf '%s\n' "$list_out" | sed -nE 's/^[0-9]+:[[:space:]]*(.+)$/\1/p' | head -n 4)
    if [ -n "$names" ]; then
      while IFS= read -r n; do
        [ -n "$n" ] && lines+=("  • $n")
      done <<<"$names"
    fi
  elif [ "$openrgb_running" -eq 1 ]; then
    lines+=("OpenRGB: daemon running")
  fi
fi

# Installed but idle → stay hidden (not "used")
if [ "$ckb_running" -eq 0 ] && [ "$openrgb_running" -eq 0 ]; then
  if [ -n "$openrgb_bin" ] || command -v ckb-next >/dev/null 2>&1; then
    emit_disconnected "RGB tools installed but idle (start OpenRGB/ckb-next)"
  fi
  emit_disconnected "No RGB stack in use"
fi

parts=()
[ "$openrgb_running" -eq 1 ] && parts+=("OpenRGB")
[ "$ckb_running" -eq 1 ] && parts+=("ckb")
label=$(IFS=/; echo "${parts[*]}")
if [ -n "$openrgb_devices" ]; then
  text=$(printf '󰃠 %s' "$openrgb_devices")
else
  text="󰃠 $label"
fi

tooltip=$(printf 'RGB\n\n%s\n\nLeft: OpenRGB · Right: ckb-next · Middle: refresh' "$(printf '%s\n' "${lines[@]}")")
write_cache_and_exit "$(emit_waybar_json "$text" "$tooltip" "normal")"
