#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
cache_file="$cache_dir/runtimes-status.json"
lock_dir="$cache_dir/runtimes-status.lock.d"
ttl="$(waybar_module_interval runtimes 600)"
stale_lock_ttl=45

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󱂬 --" "Collecting runtime status in background" "disabled"
  exit 0
fi

docker_running=0
docker_total=0
docker_unhealthy=0
docker_state="missing"

podman_running=0
podman_total=0
podman_state="missing"

vm_running=0
vm_total=0
vm_state="missing"

waydroid_state="missing"
waydroid_session="stopped"
waydroid_container="stopped"
waydroid_health="unknown"

docker_json=""
if [ -f "$cache_dir/docker-status.json" ]; then
  docker_json="$(cat "$cache_dir/docker-status.json")"
else
  docker_json="$($WAYBAR_SCRIPTS/services/containers/docker-status.sh 2>/dev/null || true)"
fi

if [ -n "$docker_json" ]; then
  docker_fields="$(printf '%s\n' "$docker_json" | jq -r '[
    (if ((.class // "") == "critical" and ((.tooltip // "") | startswith("Docker daemon unavailable"))) then
      "offline"
    elif (.engine_version? != null) then
      "online"
    elif ((.line1 // "") | length) > 0 then
      "online"
    else
      "missing"
    end),
    (.running // 0),
    (.containers // 0),
    (.unhealthy // 0)
  ] | @tsv' 2>/dev/null || true)"
  tab=$(printf '\t')
  old_ifs=$IFS
  IFS=$tab
  set -- $docker_fields
  IFS=$old_ifs

  docker_state="${1:-missing}"
  docker_running="${2:-0}"
  docker_total="${3:-0}"
  docker_unhealthy="${4:-0}"
elif command -v docker >/dev/null 2>&1; then
  docker_state="offline"
fi

if command -v podman >/dev/null 2>&1; then
  if timeout 1 podman info >/dev/null 2>&1; then
    podman_state="online"
    podman_containers=$(timeout 1 podman ps -a --format '{{.State}}' 2>/dev/null || true)
    read -r podman_total podman_running <<EOF
$(printf '%s\n' "$podman_containers" | awk '
      NF { total++ }
      tolower($0) ~ /running/ { running++ }
      END { print total + 0, running + 0 }
    ')
EOF
    if [ "$podman_total" -eq 0 ] 2>/dev/null; then
      podman_state="ready"
    fi
  else
    podman_state="offline"
  fi
fi

if command -v virsh >/dev/null 2>&1; then
  if pgrep -x virtqemud >/dev/null 2>&1 || pgrep -x libvirtd >/dev/null 2>&1; then
    virsh_out=$(timeout 1 virsh list --all 2>/dev/null || true)
    if [ -n "$virsh_out" ]; then
      vm_state="online"
      read -r vm_total vm_running <<EOF
$(printf '%s\n' "$virsh_out" | awk '
        NR > 2 && $0 !~ /^-+$/ {
          if (NF > 0) total++
          if (tolower($NF) == "running") running++
        }
        END { print total + 0, running + 0 }
      ')
EOF
    else
      vm_state="offline"
    fi
  else
    vm_state="offline"
  fi
fi

if command -v waydroid >/dev/null 2>&1; then
  status_output=$(timeout 1 waydroid status 2>/dev/null || true)
  if [ -n "$status_output" ]; then
    waydroid_state="online"
    read -r waydroid_session waydroid_container <<EOF
$(printf '%s\n' "$status_output" | awk -F':[ \t]*' '
      /^Session:/ { session=tolower($2) }
      /^Container:/ { container=tolower($2) }
      END { print (session ? session : "stopped"), (container ? container : "stopped") }
    ')
EOF
  else
    waydroid_state="offline"
  fi
fi

if [ "$waydroid_state" = "online" ]; then
  if [ "$waydroid_session" = "running" ] && [ "$waydroid_container" = "running" ]; then
    waydroid_health="healthy"
  elif [ "$waydroid_session" = "stopped" ] && [ "$waydroid_container" = "stopped" ]; then
    waydroid_health="idle"
  else
    waydroid_health="degraded"
  fi
elif [ "$waydroid_state" = "offline" ]; then
  waydroid_health="offline"
fi

active=$((docker_running + podman_running + vm_running))
if [ "$waydroid_session" = "running" ] || [ "$waydroid_container" = "running" ]; then
  active=$((active + 1))
fi

engines_online=0
for state in "$docker_state" "$podman_state" "$vm_state" "$waydroid_state"; do
  if [ "$state" = "online" ]; then
    engines_online=$((engines_online + 1))
  fi
done
engines_text=$(printf '%2d' "$engines_online")

waydroid_active=0
if [ "$waydroid_session" = "running" ] || [ "$waydroid_container" = "running" ]; then
  waydroid_active=1
fi

class="normal"
if [ "$docker_unhealthy" -gt 0 ]; then
  class="critical"
elif [ "$docker_state" = "offline" ] || [ "$podman_state" = "offline" ] || [ "$vm_state" = "offline" ]; then
  class="warning"
fi

tooltip=$(printf 'Docker: %s (running %s / total %s / unhealthy %s)\nPodman: %s (running %s / total %s)%s\nLibvirt: %s (running %s / total %s)\nWaydroid: %s (health %s / session %s / container %s)' \
  "$docker_state" "$docker_running" "$docker_total" "$docker_unhealthy" \
  "$podman_state" "$podman_running" "$podman_total" "$([ "$podman_state" = "ready" ] && printf ' - engine reachable, no containers tracked' || printf '')" \
  "$vm_state" "$vm_running" "$vm_total" \
  "$waydroid_state" "$waydroid_health" "$waydroid_session" "$waydroid_container")
# escape_markup takes an arg (does not read stdin).
tooltip=$(escape_markup "$tooltip")
tooltip=$(printf '%s\n\nLeft: virt-manager · Right: podman ps · Middle: virsh list' "$tooltip")

json=$(jq -cn \
  --arg text "󱂬 ${engines_text}" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  --arg docker_state "$docker_state" \
  --argjson docker_running "$docker_running" \
  --argjson docker_total "$docker_total" \
  --argjson docker_unhealthy "$docker_unhealthy" \
  --arg podman_state "$podman_state" \
  --argjson podman_running "$podman_running" \
  --argjson podman_total "$podman_total" \
  --arg vm_state "$vm_state" \
  --argjson vm_running "$vm_running" \
  --argjson vm_total "$vm_total" \
  --arg waydroid_state "$waydroid_state" \
  --arg waydroid_health "$waydroid_health" \
  --arg waydroid_session "$waydroid_session" \
  --arg waydroid_container "$waydroid_container" \
  '{text:$text, tooltip:$tooltip, class:$class, docker_state:$docker_state, docker_running:$docker_running, docker_total:$docker_total, docker_unhealthy:$docker_unhealthy, podman_state:$podman_state, podman_running:$podman_running, podman_total:$podman_total, vm_state:$vm_state, vm_running:$vm_running, vm_total:$vm_total, waydroid_state:$waydroid_state, waydroid_health:$waydroid_health, waydroid_session:$waydroid_session, waydroid_container:$waydroid_container}')

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
