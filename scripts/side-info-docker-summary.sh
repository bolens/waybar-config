#!/usr/bin/env sh
# side-info-docker-summary.sh: Docker summary logic for side-info-status.sh

docker_summary() {
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-side-graphs/cache"
  mkdir -p "$cache_dir"
  if command -v read_cached_summary >/dev/null 2>&1; then
    cached="$(read_cached_summary "$cache_dir" docker 2>/dev/null || true)"
    if [ -n "$cached" ]; then
      printf '%s\n' "$cached"
      return
    fi
  fi

  json="$($HOME/.config/waybar/scripts/docker-status.sh 2>/dev/null || true)"

  [ -n "$json" ] || {
    jq -cn \
      --arg line1 "$(format_lr "Docker Engine" "🔴")" \
      --arg line2 "$(format_lr "Portainer [None]" "🔴")" \
      --arg line3 "$(format_lr "Running" "0/0")" \
      --arg line4 "$(format_lr "Containers" "0")" \
      --arg line5 "$(format_lr "Paused" "0")" \
      --arg line6 "$(format_lr "Restarting" "0")" \
      --arg line7 "$(format_lr "Unhealthy" "0")" \
      --arg line8 "$(format_lr "Images" "0")" \
      --arg line9 "$(format_lr "Volumes" "0")" \
      --arg line10 "$(format_lr "Stacks" "0")" \
      --arg tooltip "Docker status unavailable" \
      --arg tooltip1 "Docker Engine appears offline (CLI missing or daemon unreachable)" \
      --arg tooltip2 "Portainer status unavailable while Docker Engine is offline" \
      --arg tooltip3 "Cannot query running container counts while engine is unavailable" \
      --arg tooltip4 "Total container inventory unavailable while Docker is offline" \
      --arg tooltip5 "Paused container list unavailable while Docker is offline" \
      --arg tooltip6 "Restarting container list unavailable while Docker is offline" \
      --arg tooltip7 "Unhealthy container list unavailable while Docker is offline" \
      --arg tooltip8 "Image inventory unavailable while Docker is offline" \
      --arg tooltip9 "Volume inventory unavailable while Docker is offline" \
      --arg tooltip10 "Compose stack inventory unavailable while Docker is offline" \
      --arg class "disabled" \
      '{line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, tooltip:$tooltip, tooltip1:$tooltip1, tooltip2:$tooltip2, tooltip3:$tooltip3, tooltip4:$tooltip4, tooltip5:$tooltip5, tooltip6:$tooltip6, tooltip7:$tooltip7, tooltip8:$tooltip8, tooltip9:$tooltip9, tooltip10:$tooltip10, class:$class}'
    return
  }

  fields="$(printf '%s' "$json" | jq -r '[.line1 // "", .line2 // "", .line3 // "", .line4 // "", .line5 // "", .line6 // "", .line7 // "", .line8 // "", .line9 // "", .line10 // "", .tooltip // "Docker status available", .class // "normal"] | @tsv')"
  tab=$(printf '\t')
  old_ifs=$IFS
  IFS=$tab
  set -- $fields
  IFS=$old_ifs
  line1="${1:-}"
  line2="${2:-}"
  line3_raw="${3:-}"
  line4_raw="${4:-}"
  line5="${5:-}"
  line6="${6:-}"
  line7="${7:-}"
  line8="${8:-}"
  line9="${9:-}"
  line10="${10:-}"
  tooltip="${11:-Docker status available}"
  class="${12:-normal}"

  running="$(printf '%s' "$json" | jq -r '.running // empty')"
  total="$(printf '%s' "$json" | jq -r '.containers // empty')"
  paused="$(printf '%s' "$json" | jq -r '.paused // empty')"
  restarting="$(printf '%s' "$json" | jq -r '.restarting // empty')"
  unhealthy="$(printf '%s' "$json" | jq -r '.unhealthy // empty')"
  images="$(printf '%s' "$json" | jq -r '.images // empty')"
  volumes="$(printf '%s' "$json" | jq -r '.volumes // empty')"
  stacks="$(printf '%s' "$json" | jq -r '.stacks // empty')"

  [ -n "$running" ] || running="$(printf '%s\n' "$line3_raw" | awk '{print $NF + 0}')"
  [ -n "$total" ] || total="$(printf '%s\n' "$line4_raw" | awk '{print $NF + 0}')"
  [ -n "$paused" ] || paused="$(printf '%s\n' "$line5" | awk '{print $NF + 0}')"
  [ -n "$restarting" ] || restarting="$(printf '%s\n' "$line6" | awk '{print $NF + 0}')"
  [ -n "$unhealthy" ] || unhealthy="$(printf '%s\n' "$line7" | awk '{print $NF + 0}')"
  [ -n "$images" ] || images="$(printf '%s\n' "$line8" | awk '{print $NF + 0}')"
  [ -n "$volumes" ] || volumes="$(printf '%s\n' "$line9" | awk '{print $NF + 0}')"
  [ -n "$stacks" ] || stacks="$(printf '%s\n' "$line10" | awk '{print $NF + 0}')"

  class3="cp-idle"
  class5="cp-idle"
  class6="cp-idle"
  class7="cp-idle"
  [ "$running" -gt 0 ] && class3="cp-ok"
  [ "$paused" -gt 0 ] && class5="cp-warn"
  [ "$restarting" -gt 0 ] && class6="cp-crit"
  [ "$unhealthy" -gt 0 ] && class7="cp-crit"

  summary="$(jq -cn \
    --arg line1 "$line1" \
    --arg line2 "$line2" \
    --arg line3 "$(format_lr "Running" "${running}/${total}")" \
    --arg line4 "$(format_lr "Containers" "${total}")" \
    --arg line5 "$line5" \
    --arg line6 "$line6" \
    --arg line7 "$line7" \
    --arg line8 "$line8" \
    --arg line9 "$line9" \
    --arg line10 "$line10" \
    --arg tooltip "$tooltip" \
    --arg tooltip1 "Docker Engine state from status snapshot" \
    --arg tooltip2 "Portainer state from status snapshot" \
    --arg tooltip3 "Running containers: ${running} of ${total}" \
    --arg tooltip4 "Total containers tracked: ${total}" \
    --arg tooltip5 "Paused containers: ${paused}" \
    --arg tooltip6 "Restarting containers: ${restarting}" \
    --arg tooltip7 "Unhealthy containers: ${unhealthy}" \
    --arg tooltip8 "Docker images: ${images}" \
    --arg tooltip9 "Docker volumes: ${volumes}" \
    --arg tooltip10 "Compose stacks: ${stacks}" \
    --arg class "$class" \
    --arg class3 "$class3" \
    --arg class5 "$class5" \
    --arg class6 "$class6" \
    --arg class7 "$class7" \
    '{line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, tooltip:$tooltip, tooltip1:$tooltip1, tooltip2:$tooltip2, tooltip3:$tooltip3, tooltip4:$tooltip4, tooltip5:$tooltip5, tooltip6:$tooltip6, tooltip7:$tooltip7, tooltip8:$tooltip8, tooltip9:$tooltip9, tooltip10:$tooltip10, class:$class, class3:$class3, class5:$class5, class6:$class6, class7:$class7}')"

  if command -v write_cached_summary >/dev/null 2>&1; then
    write_cached_summary "$cache_dir" docker "$summary"
  fi

  printf '%s\n' "$summary"
}
