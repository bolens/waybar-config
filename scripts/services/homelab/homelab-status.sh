#!/usr/bin/env bash
# Probe configured homelab HTTP targets; hide when none configured.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/homelab-status.json"
lock_dir="$cache_dir/homelab-status.lock.d"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

ttl="$(waybar_module_interval homelab 60)"
stale_lock_ttl=30
timeout_sec=$(waybar_settings_get '.homelab.timeout_sec' '3')
case "$timeout_sec" in '' | *[!0-9]*) timeout_sec=3 ;; esac
mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰒍 …" "Checking homelab targets..." "normal"
  exit 0
fi

targets_json=$(waybar_settings_get '.homelab.targets' '[]')
count=$(printf '%s' "$targets_json" | jq 'if type=="array" then length else 0 end' 2>/dev/null || echo 0)

if [ "$count" -eq 0 ]; then
  json=$(emit_waybar_json "" "Homelab: no targets in settings.homelab.targets" "hidden")
  printf '%s\n' "$json"
  printf '%s\n' "$json" >"$cache_file"
  exit 0
fi

ok=0
fail=0
lines=""
while IFS="$(printf '\t')" read -r name url expect; do
  [ -n "${name:-}" ] || continue
  [ -n "${url:-}" ] || continue
  expect="${expect:-200}"
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$timeout_sec" -L "$url" 2>/dev/null || echo "000")
  # Treat 2xx/3xx as up unless expect is an exact code
  up=0
  if [ "$expect" = "any" ] || [ "$expect" = "2xx" ]; then
    case "$code" in
      2?? | 3??) up=1 ;;
    esac
  elif [ "$code" = "$expect" ]; then
    up=1
  fi
  if [ "$up" -eq 1 ]; then
    ok=$((ok + 1))
    mark="✓"
  else
    fail=$((fail + 1))
    mark="✗"
  fi
  line=$(printf '%s  %s  HTTP %s' "$mark" "$name" "$code")
  if [ -z "$lines" ]; then
    lines="$line"
  else
    lines=$(printf '%s\n%s' "$lines" "$line")
  fi
done <<EOF
$(printf '%s' "$targets_json" | jq -r '.[] | [.name // .url, .url, (.expect // "2xx")] | @tsv' 2>/dev/null || true)
EOF

class="normal"
if [ "$fail" -gt 0 ] && [ "$ok" -eq 0 ]; then
  class="critical"
elif [ "$fail" -gt 0 ]; then
  class="warning"
fi

text="󰒍 ${ok}/${count}"
if [ "$count" -eq 1 ]; then
  hint='Left: open URL · Middle: refresh'
else
  hint='Left: pick target · Right: open first · Middle: refresh'
fi
tooltip=$(printf 'Homelab health\n%s\n\n%s' "$lines" "$hint")

json=$(emit_waybar_json "$text" "$tooltip" "$class")
printf '%s\n' "$json"
tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
