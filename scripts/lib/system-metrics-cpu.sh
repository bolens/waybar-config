#!/usr/bin/env bash
# CPU topology / counters / temperature helpers for system-metrics-collector.
# Expected caller context: cache_dir, topology_file, topology_ttl, stat_prev,
# hwmon_root, thermal_root, temp_path_file; waybar-cache-helpers sourced.
# shellcheck disable=SC2154 # variables provided by system-metrics-collector.sh

ensure_topology_file() {
  age=$(cache_file_age "$topology_file")
  if [ "$age" -le "$topology_ttl" ] 2>/dev/null && [ -f "$topology_file" ]; then
    return 0
  fi
  cores=1
  threads=1
  threads_per_core=1
  if command -v nproc >/dev/null 2>&1; then
    threads="$(nproc)"
  fi
  if command -v lscpu >/dev/null 2>&1; then
    c="$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || true)"
    tpc="$(lscpu 2>/dev/null | awk -F: '/^Thread\(s\) per core:/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || true)"
    [ -n "$c" ] && cores="$c"
    [ -n "$tpc" ] && threads_per_core="$tpc"
  fi
  tmp="$topology_file.tmp.$$"
  jq -cn \
    --argjson cores "$cores" \
    --argjson threads "$threads" \
    --argjson threads_per_core "$threads_per_core" \
    '{cores:$cores,threads:$threads,threads_per_core:$threads_per_core}' >"$tmp"
  mv -f "$tmp" "$topology_file"
}
read_cpu_counters() {
  awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8, $9; exit}' /proc/stat
}
compute_cpu_usage_percent() {
  local user nice system idle iowait irq softirq steal
  local total_now idle_now total_prev idle_prev delta_total delta_idle usage

  IFS=' ' read -r user nice system idle iowait irq softirq steal < <(read_cpu_counters)
  total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle_now=$((idle + iowait))

  if [ ! -f "$stat_prev" ]; then
    # CPU % needs two /proc/stat samples; without a prior file, take a short
    # baseline sleep so the first refresh is not stuck at 0%.
    printf '%s %s\n' "$total_now" "$idle_now" >"$stat_prev"
    sleep 0.15
    IFS=' ' read -r user nice system idle iowait irq softirq steal < <(read_cpu_counters)
    total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle_now=$((idle + iowait))
  fi

  IFS=' ' read -r total_prev idle_prev <"$stat_prev"
  printf '%s %s\n' "$total_now" "$idle_now" >"$stat_prev"

  delta_total=$((total_now - total_prev))
  delta_idle=$((idle_now - idle_prev))

  usage=0
  if [ "$delta_total" -gt 0 ]; then
    usage=$(((delta_total - delta_idle) * 100 / delta_total))
  fi
  printf '%s' "$usage"
}
find_temp_path() {
  for path in "$hwmon_root"/hwmon*/temp1_input; do
    if [ -f "$path" ]; then
      name_file="${path%/*}/name"
      if [ -f "$name_file" ]; then
        name=$(cat "$name_file" 2>/dev/null || true)
        if [ "$name" = "coretemp" ] || [ "$name" = "k10temp" ] || [ "$name" = "zenpower" ] || [ "$name" = "nouveau" ] || [ "$name" = "acpitz" ]; then
          printf '%s' "$path"
          return 0
        fi
      fi
    fi
  done
  if [ -f "$thermal_root/thermal_zone0/temp" ]; then
    printf '%s' "$thermal_root/thermal_zone0/temp"
    return 0
  fi
  return 1
}
read_cpu_temperature() {
  path=""
  if [ -f "$temp_path_file" ]; then
    path=$(cat "$temp_path_file" 2>/dev/null || true)
    if [ -n "$path" ] && [ -f "$path" ]; then
      # If it's a hwmon path, validate the sensor driver name
      if [ "${path%/temp1_input}" != "$path" ]; then
        name_file="${path%/*}/name"
        if [ -f "$name_file" ]; then
          name=$(cat "$name_file" 2>/dev/null || true)
          if [ "$name" != "coretemp" ] && [ "$name" != "k10temp" ] && [ "$name" != "zenpower" ] && [ "$name" != "nouveau" ] && [ "$name" != "acpitz" ]; then
            path=""
          fi
        else
          path=""
        fi
      fi
    else
      path=""
    fi
  fi

  if [ -z "$path" ]; then
    path=$(find_temp_path || true)
    if [ -n "$path" ]; then
      tmp_temp_path="$temp_path_file.tmp.$$"
      printf '%s' "$path" >"$tmp_temp_path"
      mv -f "$tmp_temp_path" "$temp_path_file"
    else
      tmp_temp_path="$temp_path_file.tmp.$$"
      printf '' >"$tmp_temp_path"
      mv -f "$tmp_temp_path" "$temp_path_file"
    fi
  fi

  if [ -n "$path" ] && [ -f "$path" ]; then
    raw_temp=$(cat "$path" 2>/dev/null || echo 0)
    printf '%d' $((raw_temp / 1000))
  else
    printf '0'
  fi
}
