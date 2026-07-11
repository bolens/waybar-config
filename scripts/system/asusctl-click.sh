#!/usr/bin/env bash
# Cycle / pick asusctl platform profiles.
# Usage: asusctl-click.sh next|prev|menu|<ProfileName>
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck disable=SC1091
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

target="${1:-next}"
signal_num=$(waybar_settings_get '.signals.asusctl' '28')
cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/asusctl-status.json"

resolve_asusctl() {
  if [ -n "${WAYBAR_ASUSCTL_BIN:-}" ] && [ -x "${WAYBAR_ASUSCTL_BIN}" ]; then
    printf '%s' "$WAYBAR_ASUSCTL_BIN"
    return 0
  fi
  command -v asusctl 2>/dev/null || return 1
}

notify() {
  notify-send -a ASUS "$@" 2>/dev/null || true
}

normalize_profile() {
  printf '%s' "$1" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"//; s/"$//'
}

parse_active() {
  local raw="$1" line
  line=$(printf '%s\n' "$raw" | sed -nE 's/.*[Aa]ctive profile is[[:space:]]+(.+)$/\1/p; s/.*[Aa]ctive profile:[[:space:]]*(.+)$/\1/p' | tail -n1)
  if [ -z "$line" ]; then
    line=$(printf '%s\n' "$raw" | sed '/^$/d' | grep -viE 'error|asusd|running|help|usage' | tail -n1 || true)
  fi
  normalize_profile "$line"
}

list_profiles() {
  local raw
  raw=$("$asusctl_bin" profile list 2>/dev/null || true)
  if [ -z "$raw" ]; then
    raw=$("$asusctl_bin" profile --list 2>/dev/null || true)
  fi
  printf '%s\n' "$raw" | sed '/^$/d' | grep -viE 'error|asusd|running|help|usage|available|profiles?:' \
    | while IFS= read -r line; do
        printf '%s\n' "$(normalize_profile "$line")"
      done | awk 'NF'
}

get_current() {
  local raw
  raw=$("$asusctl_bin" profile get 2>/dev/null || true)
  if [ -z "$raw" ]; then
    raw=$("$asusctl_bin" profile --profile-get 2>/dev/null || true)
  fi
  parse_active "$raw"
}

set_profile() {
  local name="$1"
  if "$asusctl_bin" profile set "$name" >/dev/null 2>&1; then
    return 0
  fi
  "$asusctl_bin" profile --profile-set="$name" >/dev/null 2>&1
}

cycle_next() {
  if "$asusctl_bin" profile next >/dev/null 2>&1; then
    return 0
  fi
  "$asusctl_bin" profile --next >/dev/null 2>&1
}

signal_refresh() {
  if [ -f "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" ]; then
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$signal_num" "$cache_file"
  else
    rm -f "$cache_file" 2>/dev/null || true
    pkill -x -RTMIN+"$signal_num" waybar >/dev/null 2>&1 || true
  fi
  "$WAYBAR_SCRIPTS/system/asusctl-status.sh" --refresh >/dev/null 2>&1 || true
}

if ! asusctl_bin="$(resolve_asusctl)"; then
  notify "ASUS" "asusctl not installed"
  exit 0
fi

current=$(get_current)
if [ -z "$current" ]; then
  notify "ASUS" "asusd not running or profiles unavailable"
  exit 0
fi

mapfile -t profiles < <(list_profiles)
if [ "${#profiles[@]}" -eq 0 ]; then
  profiles=(Quiet Balanced Performance)
fi

case "$target" in
  menu)
    if command -v rofi >/dev/null 2>&1; then
      width=$(waybar_settings_get '.rofi.asusctl.width' '280')
      lines=$(waybar_settings_get '.rofi.asusctl.lines' '4')
      selected=$(printf '%s\n' "${profiles[@]}" | rofi -dmenu -i -p "ASUS profile" \
        -theme-str "window {width: ${width}px; lines: ${lines};}")
      if [ -z "$selected" ]; then
        exit 0
      fi
      target=$(normalize_profile "$selected")
    else
      target=next
    fi
    ;;
  next|prev)
    ;;
  *)
    # Named profile (from rofi or binds)
    ;;
esac

if [ "$target" = "next" ] || [ "$target" = "prev" ]; then
  idx=-1
  i=0
  for p in "${profiles[@]}"; do
    if [ "$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$current" | tr '[:upper:]' '[:lower:]')" ]; then
      idx=$i
      break
    fi
    i=$((i + 1))
  done
  count=${#profiles[@]}
  if [ "$target" = "next" ]; then
    if [ "$idx" -lt 0 ]; then
      idx=0
    else
      idx=$(( (idx + 1) % count ))
    fi
    # Prefer native next when direction is next and list matches asusctl order
    if [ "$target" = "next" ] && cycle_next; then
      notify "ASUS" "Profile → $(get_current)"
      signal_refresh
      exit 0
    fi
  else
    if [ "$idx" -lt 0 ]; then
      idx=$((count - 1))
    else
      idx=$(( (idx - 1 + count) % count ))
    fi
  fi
  target="${profiles[$idx]}"
fi

if set_profile "$target"; then
  notify "ASUS" "Profile → $target"
else
  notify "ASUS" "Failed to set profile: $target"
  exit 1
fi
signal_refresh
