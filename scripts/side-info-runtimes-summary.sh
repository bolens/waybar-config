#!/usr/bin/env sh
# side-info-runtimes-summary.sh: Runtimes summary logic for side-info-status.sh

runtimes_summary() {
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-side-graphs/cache"
  mkdir -p "$cache_dir"
  if command -v read_cached_summary >/dev/null 2>&1; then
    cached="$(read_cached_summary "$cache_dir" runtimes 2>/dev/null || true)"
    if [ -n "$cached" ]; then
      printf '%s\n' "$cached"
      return
    fi
  fi

  rt_json="$(~/.config/waybar/scripts/runtimes-status.sh 2>/dev/null || true)"
  [ -n "$rt_json" ] || {
    jq -cn \
      --arg line1 "$(format_lr "Engines ready" "0/4")" \
      --arg line2 "$(format_lr "Active work" "0")" \
      --arg line3 "$(format_lr "Docker" "n/a")" \
      --arg line4 "$(format_lr "Unhealthy" "0")" \
      --arg line5 "$(format_lr "Podman" "n/a")" \
      --arg line6 "$(format_lr "Libvirt" "n/a")" \
      --arg line7 "$(format_lr "Waydroid [Engine]" "⚪")" \
      --arg line8 "$(format_lr "Waydroid [Health]" "⚪")" \
      --arg line9 "$(format_lr "Waydroid [Session]" "⚪")" \
      --arg line10 "$(format_lr "Waydroid [Container]" "⚪")" \
      --arg line11 "$(format_lr "Waydroid [Mismatch]" "n/a")" \
      --arg line12 "$(format_lr "Waydroid [Act]" "check")" \
      --arg tooltip "Runtime summary unavailable" \
      --arg class7 "cp-idle" \
      --arg class8 "cp-idle" \
      --arg class9 "cp-idle" \
      --arg class10 "cp-idle" \
      --arg class11 "cp-idle" \
      --arg class12 "cp-idle" \
      --arg class "disabled" \
      '{line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, line11:$line11, line12:$line12, tooltip:$tooltip, class7:$class7, class8:$class8, class9:$class9, class10:$class10, class11:$class11, class12:$class12, class:$class}'
    return
  }

  fields="$(printf '%s' "$rt_json" | jq -r '[
    (.tooltip // ""),
    (.docker_state // ""),
    ((.docker_running // "") | tostring),
    ((.docker_total // "") | tostring),
    ((.docker_unhealthy // "") | tostring),
    (.podman_state // ""),
    ((.podman_running // "") | tostring),
    ((.podman_total // "") | tostring),
    (.vm_state // ""),
    ((.vm_running // "") | tostring),
    ((.vm_total // "") | tostring),
    (.waydroid_state // ""),
    (.waydroid_health // ""),
    (.waydroid_session // ""),
    (.waydroid_container // "")
  ] | @tsv')"
  tab="$(printf '\t')"
  old_ifs=$IFS
  IFS=$tab
  set -- $fields
  IFS=$old_ifs

  rt_tooltip="${1:-}"
  docker_state="${2:-}"
  docker_running="${3:-}"
  docker_total="${4:-}"
  docker_unhealthy="${5:-}"
  podman_state="${6:-}"
  podman_running="${7:-}"
  podman_total="${8:-}"
  vm_state="${9:-}"
  vm_running="${10:-}"
  vm_total="${11:-}"
  waydroid_state="${12:-}"
  waydroid_health="${13:-}"
  waydroid_session="${14:-}"
  waydroid_container="${15:-}"

  if [ -z "$docker_state" ] || [ -z "$podman_state" ] || [ -z "$vm_state" ] || [ -z "$waydroid_state" ]; then
    docker_line="$(printf '%s\n' "$rt_tooltip" | awk -F': ' '/^Docker:/ {print $2; exit}')"
    podman_line="$(printf '%s\n' "$rt_tooltip" | awk -F': ' '/^Podman:/ {print $2; exit}')"
    libvirt_line="$(printf '%s\n' "$rt_tooltip" | awk -F': ' '/^Libvirt:/ {print $2; exit}')"
    waydroid_line="$(printf '%s\n' "$rt_tooltip" | awk -F': ' '/^Waydroid:/ {print $2; exit}')"

    [ -n "$docker_state" ] || docker_state="$(printf '%s\n' "$docker_line" | awk '{print $1; exit}')"
    [ -n "$docker_running" ] || docker_running="$(printf '%s\n' "$docker_line" | sed -n 's/.*running \([0-9][0-9]*\) \/ total \([0-9][0-9]*\).*/\1/p')"
    [ -n "$docker_total" ] || docker_total="$(printf '%s\n' "$docker_line" | sed -n 's/.*running \([0-9][0-9]*\) \/ total \([0-9][0-9]*\).*/\2/p')"
    [ -n "$docker_unhealthy" ] || docker_unhealthy="$(printf '%s\n' "$docker_line" | sed -n 's/.*unhealthy \([0-9][0-9]*\)).*/\1/p')"

    [ -n "$podman_state" ] || podman_state="$(printf '%s\n' "$podman_line" | awk '{print $1; exit}')"
    [ -n "$podman_running" ] || podman_running="$(printf '%s\n' "$podman_line" | sed -n 's/.*running \([0-9][0-9]*\) \/ total \([0-9][0-9]*\).*/\1/p')"
    [ -n "$podman_total" ] || podman_total="$(printf '%s\n' "$podman_line" | sed -n 's/.*running \([0-9][0-9]*\) \/ total \([0-9][0-9]*\).*/\2/p')"

    [ -n "$vm_state" ] || vm_state="$(printf '%s\n' "$libvirt_line" | awk '{print $1; exit}')"
    [ -n "$vm_running" ] || vm_running="$(printf '%s\n' "$libvirt_line" | sed -n 's/.*running \([0-9][0-9]*\) \/ total \([0-9][0-9]*\).*/\1/p')"
    [ -n "$vm_total" ] || vm_total="$(printf '%s\n' "$libvirt_line" | sed -n 's/.*running \([0-9][0-9]*\) \/ total \([0-9][0-9]*\).*/\2/p')"

    [ -n "$waydroid_state" ] || waydroid_state="$(printf '%s\n' "$waydroid_line" | awk '{print $1; exit}')"
    [ -n "$waydroid_health" ] || waydroid_health="$(printf '%s\n' "$waydroid_line" | sed -n 's/.*health[[:space:]]*\([^[:space:]/)]*\)[[:space:]]*\/[[:space:]]*session.*/\1/p')"
    [ -n "$waydroid_session" ] || waydroid_session="$(printf '%s\n' "$waydroid_line" | sed -n 's/.*session[[:space:]]*\([^[:space:]/)]*\)[[:space:]]*\/[[:space:]]*container.*/\1/p')"
    [ -n "$waydroid_container" ] || waydroid_container="$(printf '%s\n' "$waydroid_line" | sed -n 's/.*container[[:space:]]*\([^[:space:])]*\).*/\1/p')"
  fi

  waydroid_state="$(normalize_token "$waydroid_state")"
  waydroid_health="$(normalize_token "$waydroid_health")"
  waydroid_session="$(normalize_token "$waydroid_session")"
  waydroid_container="$(normalize_token "$waydroid_container")"

# Ensure helpers are sourced
script_dir="$(dirname "$0")"
. "$script_dir/side-info-helpers.sh"

  if [ -z "$waydroid_health" ]; then
    if [ "$waydroid_state" = "online" ]; then
      if [ "$waydroid_session" = "running" ] && [ "$waydroid_container" = "running" ]; then
        waydroid_health='healthy'
      elif [ "$waydroid_session" = "stopped" ] && [ "$waydroid_container" = "stopped" ]; then
        waydroid_health='idle'
      else
        waydroid_health='degraded'
      fi
    elif [ "$waydroid_state" = "offline" ]; then
      waydroid_health='offline'
    else
      waydroid_health='unknown'
    fi
  fi

  case "$waydroid_health" in
    healthy) waydroid_health_circle='🟢' ;;
    idle) waydroid_health_circle='⚪' ;;
    degraded) waydroid_health_circle='🟠' ;;
    offline) waydroid_health_circle='🔴' ;;
    *) waydroid_health_circle='⚪' ;;
  esac

  case "$waydroid_state" in
    online) waydroid_engine_circle='🟢' ;;
    offline) waydroid_engine_circle='🔴' ;;
    missing) waydroid_engine_circle='⚪' ;;
    *) waydroid_engine_circle='🟠' ;;
  esac

  case "$waydroid_state" in
    online) waydroid_engine_class='cp-ok' ;;
    offline) waydroid_engine_class='cp-crit' ;;
    missing) waydroid_engine_class='cp-idle' ;;
    *) waydroid_engine_class='cp-warn' ;;
  esac

  case "$waydroid_session" in
    running) waydroid_session_circle='🟢' ;;
    stopped)
      if [ "$waydroid_state" = "offline" ]; then
        waydroid_session_circle='🔴'
      else
        waydroid_session_circle='⚪'
      fi
      ;;
    *)
      if [ "$waydroid_state" = "offline" ]; then
        waydroid_session_circle='🔴'
      else
        waydroid_session_circle='🟠'
      fi
      ;;
  esac

  case "$waydroid_session_circle" in
    '🟢') waydroid_session_class='cp-ok' ;;
    '🔴') waydroid_session_class='cp-crit' ;;
    '🟠') waydroid_session_class='cp-warn' ;;
    *) waydroid_session_class='cp-idle' ;;
  esac

  case "$waydroid_container" in
    running) waydroid_container_circle='🟢' ;;
    stopped)
      if [ "$waydroid_state" = "offline" ]; then
        waydroid_container_circle='🔴'
      else
        waydroid_container_circle='⚪'
      fi
      ;;
    *)
      if [ "$waydroid_state" = "offline" ]; then
        waydroid_container_circle='🔴'
      else
        waydroid_container_circle='🟠'
      fi
      ;;
  esac

  case "$waydroid_container_circle" in
    '🟢') waydroid_container_class='cp-ok' ;;
    '🔴') waydroid_container_class='cp-crit' ;;
    '🟠') waydroid_container_class='cp-warn' ;;
    *) waydroid_container_class='cp-idle' ;;
  esac

  waydroid_mismatch='n/a'
  waydroid_mismatch_circle='⚪'
  if [ "$waydroid_state" = "online" ]; then
    if [ "$waydroid_session" = "$waydroid_container" ]; then
      if [ "$waydroid_session" = "running" ]; then
        waydroid_mismatch='no'
        waydroid_mismatch_circle='🟢'
      elif [ "$waydroid_session" = "stopped" ]; then
        waydroid_mismatch='no'
        waydroid_mismatch_circle='⚪'
      else
        waydroid_mismatch='no'
        waydroid_mismatch_circle='🟠'
      fi
    else
      waydroid_mismatch='yes'
      waydroid_mismatch_circle='🟠'
    fi
  elif [ "$waydroid_state" = "offline" ]; then
    waydroid_mismatch='n/a'
    waydroid_mismatch_circle='🔴'
  fi

  case "$waydroid_health" in
    healthy) waydroid_health_class='cp-ok' ;;
    degraded) waydroid_health_class='cp-warn' ;;
    offline) waydroid_health_class='cp-crit' ;;
    *) waydroid_health_class='cp-idle' ;;
  esac

  case "$waydroid_mismatch_circle" in
    '🟢') waydroid_mismatch_class='cp-ok' ;;
    '🔴') waydroid_mismatch_class='cp-crit' ;;
    '🟠') waydroid_mismatch_class='cp-warn' ;;
    *) waydroid_mismatch_class='cp-idle' ;;
  esac

  waydroid_action='inspect'
  waydroid_action_tooltip='Inspect Waydroid runtime state: run "waydroid status" and check service state before taking action.'
  if [ "$waydroid_state" = "offline" ]; then
    waydroid_action='start'
    waydroid_action_tooltip='Engine appears offline. Suggested sequence: 1) waydroid status 2) sudo systemctl status waydroid-container 3) sudo systemctl start waydroid-container 4) waydroid session start'
  elif [ "$waydroid_health" = "healthy" ]; then
    waydroid_action='none'
    waydroid_action_tooltip='Waydroid is healthy: engine online, session running, and container running.'
  elif [ "$waydroid_health" = "idle" ]; then
    waydroid_action='start-session'
    waydroid_action_tooltip='Waydroid is idle (session and container stopped). Start a user session with: waydroid session start'
  elif [ "$waydroid_health" = "degraded" ]; then
    waydroid_action='restart'
    if [ "$waydroid_session" = "running" ] && [ "$waydroid_container" = "stopped" ]; then
      waydroid_action_tooltip='Session is running while container is stopped. Suggested recovery: 1) waydroid session stop 2) sudo systemctl restart waydroid-container 3) waydroid session start'
    elif [ "$waydroid_session" = "stopped" ] && [ "$waydroid_container" = "running" ]; then
      waydroid_action_tooltip='Container is running but session is stopped. Start session with: waydroid session start. If it fails, restart container service and retry.'
    else
      waydroid_action_tooltip='Waydroid state is inconsistent. Try controlled restart: waydroid session stop; sudo systemctl restart waydroid-container; waydroid session start'
    fi
  fi

  case "$waydroid_action" in
    none) waydroid_action_class='cp-ok' ;;
    inspect) waydroid_action_class='cp-idle' ;;
    *) waydroid_action_class='cp-warn' ;;
  esac

  [ -n "$docker_running" ] || docker_running='0'
  [ -n "$docker_total" ] || docker_total='0'
  [ -n "$docker_unhealthy" ] || docker_unhealthy='0'
  [ -n "$podman_running" ] || podman_running='0'
  [ -n "$podman_total" ] || podman_total='0'
  [ -n "$vm_running" ] || vm_running='0'
  [ -n "$vm_total" ] || vm_total='0'

  engines_ready=0
  for state in "$docker_state" "$podman_state" "$vm_state" "$waydroid_state"; do
    case "$state" in
      online|ready) engines_ready=$((engines_ready + 1)) ;;
    esac
  done

  waydroid_active=0
  if [ "$waydroid_session" = "running" ] || [ "$waydroid_container" = "running" ]; then
    waydroid_active=1
  fi
  containers_running=$((docker_running + podman_running))
  containers_total=$((docker_total + podman_total))
  active_workloads=$((containers_running + vm_running + waydroid_active))

  summary="$(jq -cn \
    --arg line1 "$(format_lr "Engines ready" "${engines_ready}/4")" \
    --arg line2 "$(format_lr "Active work" "$active_workloads")" \
    --arg line3 "$(format_lr "Docker" "${docker_running}/${docker_total}")" \
    --arg line4 "$(format_lr "Unhealthy" "$docker_unhealthy")" \
    --arg line5 "$(format_lr "Podman" "${podman_running}/${podman_total}")" \
    --arg line6 "$(format_lr "Libvirt" "${vm_running}/${vm_total}")" \
    --arg line7 "$(format_lr "Waydroid [Engine]" "${waydroid_engine_circle}")" \
    --arg line8 "$(format_lr "Waydroid [Health]" "${waydroid_health_circle}")" \
    --arg line9 "$(format_lr "Waydroid [Session]" "${waydroid_session_circle}")" \
    --arg line10 "$(format_lr "Waydroid [Container]" "${waydroid_container_circle}")" \
    --arg line11 "$(format_lr "Waydroid [Mismatch]" "${waydroid_mismatch_circle}")" \
    --arg line12 "$(format_lr "Waydroid [Act]" "$waydroid_action")" \
    --arg tooltip "$rt_tooltip" \
    --arg tooltip1 "Runtime engines ready: ${engines_ready}/4." \
    --arg tooltip2 "Active workloads: ${active_workloads} across containers, VMs, and Waydroid." \
    --arg tooltip3 "Docker state: ${docker_line:-unavailable}" \
    --arg tooltip4 "Docker unhealthy containers: ${docker_unhealthy}." \
    --arg tooltip5 "Podman state: ${podman_line:-unavailable}" \
    --arg tooltip6 "Libvirt state: ${libvirt_line:-unavailable}" \
    --arg tooltip7 "Waydroid engine: ${waydroid_state:-unavailable} (${waydroid_engine_circle}). If offline, verify service with: sudo systemctl status waydroid-container" \
    --arg tooltip8 "Waydroid combined health: ${waydroid_health:-unknown} (${waydroid_health_circle}). Health is derived from session/container alignment and engine availability." \
    --arg tooltip9 "Waydroid session state: ${waydroid_session:-n/a} (${waydroid_session_circle}). Session represents user-facing Android runtime workload." \
    --arg tooltip10 "Waydroid container state: ${waydroid_container:-n/a} (${waydroid_container_circle}). Container represents Android base runtime availability." \
    --arg tooltip11 "Session/container mismatch: ${waydroid_mismatch}. Session=${waydroid_session:-n/a}, container=${waydroid_container:-n/a}. A mismatch often indicates partial startup or failed teardown." \
    --arg tooltip12 "$waydroid_action_tooltip" \
    --arg class7 "$waydroid_engine_class" \
    --arg class8 "$waydroid_health_class" \
    --arg class9 "$waydroid_session_class" \
    --arg class10 "$waydroid_container_class" \
    --arg class11 "$waydroid_mismatch_class" \
    --arg class12 "$waydroid_action_class" \
    --arg class "normal" \
    '{line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, line11:$line11, line12:$line12, tooltip:$tooltip, tooltip1:$tooltip1, tooltip2:$tooltip2, tooltip3:$tooltip3, tooltip4:$tooltip4, tooltip5:$tooltip5, tooltip6:$tooltip6, tooltip7:$tooltip7, tooltip8:$tooltip8, tooltip9:$tooltip9, tooltip10:$tooltip10, tooltip11:$tooltip11, tooltip12:$tooltip12, class7:$class7, class8:$class8, class9:$class9, class10:$class10, class11:$class11, class12:$class12, class:$class}')"

  if command -v write_cached_summary >/dev/null 2>&1; then
    write_cached_summary "$cache_dir" runtimes "$summary"
  fi

  printf '%s\n' "$summary"
}
