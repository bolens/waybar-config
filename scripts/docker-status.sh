#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
cache_file="$cache_dir/docker-status.json"
lock_dir="$cache_dir/docker-status.lock.d"
ttl="$(waybar_module_interval docker 30)"
stale_lock_ttl=20

mkdir -p "$cache_dir"


if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰡨 ..." "Refreshing Docker status in background" "disabled"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  jq -cn \
    --arg text "󰡨 --" \
    --arg line1 "$(printf '%-18s %s' 'Docker Engine' '--')" \
    --arg line2 "$(printf '%-18s %s' 'Portainer [None]' '--')" \
    --arg line3 "$(printf '%-18s %s' 'Running' '--')" \
    --arg line4 "$(printf '%-18s %s' 'Containers' '--')" \
    --arg line5 "$(printf '%-18s %s' 'Paused' '--')" \
    --arg line6 "$(printf '%-18s %s' 'Restarting' '--')" \
    --arg line7 "$(printf '%-18s %s' 'Unhealthy' '--')" \
    --arg line8 "$(printf '%-18s %s' 'Images' '--')" \
    --arg line9 "$(printf '%-18s %s' 'Volumes' '--')" \
    --arg line10 "$(printf '%-18s %s' 'Stacks' '--')" \
    --arg tooltip "Docker CLI not installed" \
    --arg class "disabled" \
    '{text:$text, line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, tooltip:$tooltip, class:$class}'
  exit 0
fi

# Get docker version (cache for 1 hour to prevent redundant docker daemon requests)
version_cache="$cache_dir/docker-version.txt"
if [ -f "$version_cache" ] && [ "$(cache_file_age "$version_cache")" -lt 3600 ] 2>/dev/null; then
  engine_version=$(cat "$version_cache" 2>/dev/null || echo "unknown")
else
  engine_version=$(timeout 2 docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "unknown")
  if [ "$engine_version" != "unknown" ]; then
    tmp_ver="$version_cache.tmp.$$"
    printf '%s\n' "$engine_version" > "$tmp_ver"
    mv -f "$tmp_ver" "$version_cache"
  fi
fi

# Run docker ps to fetch active containers. We capture status and image fields.
container_rows=$(timeout 3 docker ps -a --format '{{.Status}}|{{.Image}}' 2>/dev/null || true)
if [ -z "$container_rows" ] && [ "$engine_version" = "unknown" ]; then
  # Verify if daemon is actually down
  if ! timeout 2 docker ps -a >/dev/null 2>&1; then
    emit_waybar_json "󰡨 --" "Docker daemon unavailable" "critical"
    exit 0
  fi
fi

# Extract statuses using a single awk invocation.
# We count total, running (Up), paused, restarting, unhealthy, and search for Portainer image.
read -r containers running unhealthy paused restarting portainer_found <<EOF
$(printf '%s\n' "$container_rows" | awk -F'|' '
  NF>=2 {
    c++
    st = tolower($1)
    img = tolower($2)
    if (st ~ /^up/) r++
    if (st ~ /unhealthy/) u++
    if (st ~ /paused/) p++
    if (st ~ /restarting/) re++
    if (img ~ /portainer\/portainer/) port=1
  }
  END {
    print c+0, r+0, u+0, p+0, re+0, port+0
  }
')
EOF

if [ "${portainer_found:-0}" -eq 1 ]; then
  portainer_status="Online"
else
  portainer_status="--"
fi

# Cache images, volumes, stacks counts for 5 minutes (300s).
# Swarm stacks are only queried if the Docker node is part of an active Swarm.
stats_cache="$cache_dir/docker-stats-counts.txt"
if [ -f "$stats_cache" ] && [ "$(cache_file_age "$stats_cache")" -lt 300 ] 2>/dev/null; then
  read -r images volumes stacks < "$stats_cache" 2>/dev/null || { images="0"; volumes="0"; stacks="0"; }
else
  images=$(timeout 1 docker images -q 2>/dev/null | awk 'END {print NR + 0}' || printf '0')
  volumes=$(timeout 1 docker volume ls -q 2>/dev/null | awk 'END {print NR + 0}' || printf '0')
  swarm_state=$(timeout 1 docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
  if [ "$swarm_state" = "active" ]; then
    stacks=$(timeout 1 docker stack ls 2>/dev/null | awk 'END {print NR + 0}' || printf '0')
  else
    stacks="0"
  fi
  tmp_stats="$stats_cache.tmp.$$"
  printf '%s %s %s\n' "$images" "$volumes" "$stacks" > "$tmp_stats"
  mv -f "$tmp_stats" "$stats_cache"
fi

# Compose lines
line1=$(printf '%-18s %s' 'Docker Engine' "$engine_version")
line2=$(printf '%-18s %s' 'Portainer' "$portainer_status")
line3=$(printf '%-18s %s' 'Running' "$running")
line4=$(printf '%-18s %s' 'Containers' "$containers")
line5=$(printf '%-18s %s' 'Paused' "$paused")
line6=$(printf '%-18s %s' 'Restarting' "$restarting")
line7=$(printf '%-18s %s' 'Unhealthy' "$unhealthy")
line8=$(printf '%-18s %s' 'Images' "$images")
line9=$(printf '%-18s %s' 'Volumes' "$volumes")
line10=$(printf '%-18s %s' 'Stacks' "$stacks")

class="normal"
if [ "$unhealthy" -gt 0 ]; then
  class="critical"
elif [ "$paused" -gt 0 ] || [ "$restarting" -gt 0 ]; then
  class="warning"
fi

tooltip=$(printf 'Docker Engine: online\nRunning: %s\nTotal: %s\nUnhealthy: %s\nPaused: %s\nRestarting: %s' \
  "$running" "$containers" "$unhealthy" "$paused" "$restarting")

if [ "$unhealthy" -gt 0 ]; then
  tooltip=$(printf '%s\nUnhealthy containers present (open lazydocker for details)' "$tooltip")
fi
tooltip=$(printf '%b' "$tooltip" | escape_markup)

text=$(printf '󰡨 %s/%s' "$running" "$containers")

json=$(jq -cn \
  --arg text "$text" \
  --arg line1 "$line1" \
  --arg line2 "$line2" \
  --arg line3 "$line3" \
  --arg line4 "$line4" \
  --arg line5 "$line5" \
  --arg line6 "$line6" \
  --arg line7 "$line7" \
  --arg line8 "$line8" \
  --arg line9 "$line9" \
  --arg line10 "$line10" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  --arg engine_version "$engine_version" \
  --arg portainer_status "$portainer_status" \
  --argjson running "$running" \
  --argjson containers "$containers" \
  --argjson paused "$paused" \
  --argjson restarting "$restarting" \
  --argjson unhealthy "$unhealthy" \
  --argjson images "$images" \
  --argjson volumes "$volumes" \
  --argjson stacks "$stacks" \
  '{text:$text, line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, tooltip:$tooltip, class:$class, engine_version:$engine_version, portainer_status:$portainer_status, running:$running, containers:$containers, paused:$paused, restarting:$restarting, unhealthy:$unhealthy, images:$images, volumes:$volumes, stacks:$stacks}')

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"