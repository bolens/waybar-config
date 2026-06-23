#!/usr/bin/env sh
# Shared CPU / memory / GPU metrics for Waybar (one refresh serves all monitors).
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
cache_file="$cache_dir/system-metrics.json"
lock_dir="$cache_dir/system-metrics.lock.d"
stat_prev="$cache_dir/cpu-stat.prev"
topology_file="$cache_dir/cpu-topology.json"

ttl=8
topology_ttl=86400
stale_lock_ttl=30

mkdir -p "$cache_dir"

# ensure_topology_file: Discovers CPU core/thread count. Topology changes are rare, 
# so we cache this discovery for 24 hours (86400s) to avoid running lscpu on every poll.
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

# read_cpu_counters: Reads aggregate CPU ticks from /proc/stat. 
# Returns ticks for: user, nice, system, idle, iowait, irq, softirq, steal.
read_cpu_counters() {
  awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8, $9; exit}' /proc/stat
}

# compute_cpu_usage_percent: Calculates CPU load over time by comparing current 
# counters with a previously saved state in stat_prev.
compute_cpu_usage_percent() {
  set -- $(read_cpu_counters)
  user="$1"
  nice="$2"
  system="$3"
  idle="$4"
  iowait="$5"
  irq="$6"
  softirq="$7"
  steal="$8"

  total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle_now=$((idle + iowait))

  if [ ! -f "$stat_prev" ]; then
    printf '%s %s\n' "$total_now" "$idle_now" >"$stat_prev"
    sleep 0.15
    set -- $(read_cpu_counters)
    user="$1"
    nice="$2"
    system="$3"
    idle="$4"
    iowait="$5"
    irq="$6"
    softirq="$7"
    steal="$8"
    total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle_now=$((idle + iowait))
  fi

  set -- $(cat "$stat_prev")
  total_prev="$1"
  idle_prev="$2"

  printf '%s %s\n' "$total_now" "$idle_now" >"$stat_prev"

  delta_total=$((total_now - total_prev))
  delta_idle=$((idle_now - idle_prev))

  usage=0
  if [ "$delta_total" -gt 0 ]; then
    usage=$(((delta_total - delta_idle) * 100 / delta_total))
  fi
  printf '%s' "$usage"
}


if [ "${1:-}" != "--refresh" ]; then
  age=$(cache_file_age "$cache_file")
  if [ "$age" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    exit 0
  fi

  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"

  if [ -f "$cache_file" ]; then
    [ -d "$lock_dir" ] || refresh_in_background
    cat "$cache_file"
    exit 0
  fi

  [ -d "$lock_dir" ] || refresh_in_background
  jq -cn \
    '{
      cpu: {
        usage: 0,
        topology: { cores: 0, threads: 0, threads_per_core: 1 },
        load: {
          one: "0.00",
          five: "0.00",
          fifteen: "0.00",
          runnable: "0/0",
          pct: { one: 0, five: 0, fifteen: 0 }
        }
      },
      memory: {
        mem_used_gib: "0.0",
        mem_total_gib: "0.0",
        mem_pct: 0,
        swap_used_gib: "0.0",
        swap_total_gib: "0.0"
      },
      gpu: {
        available: false
      }
    }'
  exit 0
fi

temp_path_file="$cache_dir/cpu-temp-path.txt"

# find_temp_path: Scans hwmon system paths to locate a valid CPU temperature input file.
# Matches specific drivers (intel coretemp, AMD k10temp, zenpower, nouveau, acpitz) to
# filter out motherboard fan speeds or other auxiliary temperature sensors.
find_temp_path() {
  for path in /sys/class/hwmon/hwmon*/temp1_input; do
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
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    printf '/sys/class/thermal/thermal_zone0/temp'
    return 0
  fi
  return 1
}

# read_cpu_temperature: Retrieves current CPU temperature in Celsius.
# Cache path search is stored in temp_path_file to avoid scanning sysfs directories
# on every poll. Performs validation checks to ensure the sensor driver name remains valid.
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
      printf '%s' "$path" > "$tmp_temp_path"
      mv -f "$tmp_temp_path" "$temp_path_file"
    else
      tmp_temp_path="$temp_path_file.tmp.$$"
      printf '' > "$tmp_temp_path"
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

ensure_topology_file
read -r cores threads threads_per_core <<EOF
$(jq -r '[.cores // 1, .threads // 1, .threads_per_core // 1] | @tsv' "$topology_file")
EOF

usage="$(compute_cpu_usage_percent)"
cpu_temp="$(read_cpu_temperature)"

# Read load average directly using shell builtin
read -r load_1 load_5 load_15 runnable _ < /proc/loadavg

# Consolidate 3 separate load percentage calculations into a single awk process
read -r load_pct_1 load_pct_5 load_pct_15 <<EOF
$(awk -v l1="$load_1" -v l5="$load_5" -v l15="$load_15" -v th="$threads" \
  'BEGIN { printf "%.0f %.0f %.0f\n", (l1/th)*100, (l5/th)*100, (l15/th)*100 }')
EOF

mem_info=$(awk '
  /^MemTotal:/ {total=$2}
  /^MemAvailable:/ {avail=$2}
  /^SwapTotal:/ {stotal=$2}
  /^SwapFree:/ {sfree=$2}
  END {
    used = total - avail
    pct = (total > 0) ? int(used * 100 / total) : 0
    sused = stotal - sfree
    printf "%d %d %d %d %d %.1f %.1f %.1f %.1f\n", 
      total, avail, stotal, sfree, pct,
      used / 1048576, total / 1048576, sused / 1048576, stotal / 1048576
  }
' /proc/meminfo)

set -- $mem_info
mem_total_kib="${1:-0}"
mem_available_kib="${2:-0}"
swap_total_kib="${3:-0}"
swap_free_kib="${4:-0}"
mem_pct="${5:-0}"
mem_used_gib="${6:-0.0}"
mem_total_gib="${7:-0.0}"
swap_used_gib="${8:-0.0}"
swap_total_gib="${9:-0.0}"

gpu_available="false"
gpu_suspended="false"
gpu_name=""
gpu_util=0
gpu_temp=0
gpu_mem_used=0
gpu_mem_total=0
gpu_vram_pct=0
gpu_fan=0

gpu_path_file="$cache_dir/gpu-pci-path.txt"

# find_gpu_path: Discovers NVIDIA PCI device path. 0x10de is the vendor ID for NVIDIA.
find_gpu_path() {
  for dev in /sys/bus/pci/devices/*; do
    if [ -f "$dev/vendor" ] && [ "$(cat "$dev/vendor")" = "0x10de" ]; then
      printf '%s' "$dev"
      return 0
    fi
  done
  return 1
}

if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_dev=""
  if [ -f "$gpu_path_file" ]; then
    gpu_dev=$(cat "$gpu_path_file" 2>/dev/null || true)
    if [ -n "$gpu_dev" ] && [ -f "$gpu_dev/vendor" ]; then
      if [ "$(cat "$gpu_dev/vendor" 2>/dev/null)" != "0x10de" ]; then
        gpu_dev=""
      fi
    else
      gpu_dev=""
    fi
  fi

  if [ -z "$gpu_dev" ]; then
    dev=$(find_gpu_path || true)
    if [ -n "$dev" ]; then
      gpu_dev="$dev"
      tmp_gpu_path="$gpu_path_file.tmp.$$"
      printf '%s' "$gpu_dev" > "$tmp_gpu_path"
      mv -f "$tmp_gpu_path" "$gpu_path_file"
    else
      tmp_gpu_path="$gpu_path_file.tmp.$$"
      printf '' > "$tmp_gpu_path"
      mv -f "$tmp_gpu_path" "$gpu_path_file"
    fi
  fi

  # Check if NVIDIA GPU is runtime-suspended. Calling nvidia-smi while the device 
  # is suspended will wake it up (causing lag spikes and increasing power consumption).
  # Instead, if suspended, we return cached/suspended state without waking the GPU.
  if [ -n "$gpu_dev" ] && [ -f "$gpu_dev/power/runtime_status" ]; then
    if [ "$(cat "$gpu_dev/power/runtime_status")" = "suspended" ]; then
      gpu_suspended="true"
    fi
  fi

  if [ "$gpu_suspended" = "true" ]; then
    gpu_available="true"
    gpu_name="NVIDIA GPU"
    if [ -f "$cache_file" ]; then
      gpu_name=$(jq -r '.gpu.name // "NVIDIA GPU"' "$cache_file" 2>/dev/null || echo "NVIDIA GPU")
      gpu_name="${gpu_name% (Suspended)}"
    fi
    gpu_name="$gpu_name (Suspended)"
  else
    line=$(timeout 2 nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,fan.speed --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)
    if [ -n "$line" ]; then
      gpu_available="true"
      tab=$(printf '\t')
      gpu_fields=$(printf '%s\n' "$line" | awk -F', *' -v OFS='\t' '{
        gsub(/^ +| +$/,"", $1);
        print $1, int($2), int($3), int($4), int($5), int($6)
      }')
      
      old_ifs=$IFS
      IFS=$tab
      set -- $gpu_fields
      IFS=$old_ifs
      
      gpu_name="${1:-}"
      gpu_util="${2:-0}"
      gpu_temp="${3:-0}"
      gpu_mem_used="${4:-0}"
      gpu_mem_total="${5:-0}"
      gpu_fan="${6:-0}"
      
      if [ "${gpu_mem_total:-0}" -gt 0 ] 2>/dev/null; then
        gpu_vram_pct=$((gpu_mem_used * 100 / gpu_mem_total))
      fi
    fi
  fi
fi

# Retrieve top CPU processes. We cache this query for 24s to avoid expensive 'ps' calls on every poll.
# The write is done atomically to prevent other modules from reading incomplete JSON configurations.
cpu_top_file="$cache_dir/cpu-top.json"
if [ "$(cache_file_age "$cpu_top_file")" -ge 24 ] 2>/dev/null || [ ! -f "$cpu_top_file" ]; then
  cpu_top=$(ps -eo pcpu,comm --sort=-pcpu 2>/dev/null | awk '
    NR>1 && NR<=4 {
      pcpu=$1; $1=""
      sub(/^ +/, "")
      gsub(/"/, "\\\"", $0)
      items = items (items ? "," : "") "\"" $0 " (" pcpu "%)\""
    }
    END {
      print "[" items "]"
    }
  ')
  [ -z "$cpu_top" ] || [ "$cpu_top" = "null" ] && cpu_top="[]"
  tmp_cpu_top="$cpu_top_file.tmp.$$"
  printf '%s\n' "$cpu_top" > "$tmp_cpu_top"
  mv -f "$tmp_cpu_top" "$cpu_top_file"
else
  cpu_top=$(cat "$cpu_top_file" 2>/dev/null || echo "[]")
fi

# Retrieve top memory consuming processes. Cached for 24s and written atomically.
mem_top_file="$cache_dir/mem-top.json"
if [ "$(cache_file_age "$mem_top_file")" -ge 24 ] 2>/dev/null || [ ! -f "$mem_top_file" ]; then
  mem_top=$(ps -eo pmem,rss,comm --sort=-rss 2>/dev/null | awk '
    NR>1 && NR<=4 {
      pmem=$1; rss=$2; $1=""; $2=""
      sub(/^ +/, "")
      gsub(/"/, "\\\"", $0)
      if (rss > 1048576) {
        size=sprintf("%.1f GiB", rss/1048576)
      } else {
        size=sprintf("%d MiB", rss/1024)
      }
      items = items (items ? "," : "") "\"" $0 " (" size ")\""
    }
    END {
      print "[" items "]"
    }
  ')
  [ -z "$mem_top" ] || [ "$mem_top" = "null" ] && mem_top="[]"
  tmp_mem_top="$mem_top_file.tmp.$$"
  printf '%s\n' "$mem_top" > "$tmp_mem_top"
  mv -f "$tmp_mem_top" "$mem_top_file"
else
  mem_top=$(cat "$mem_top_file" 2>/dev/null || echo "[]")
fi

old_json="{}"
if [ -f "$cache_file" ]; then
  old_json=$(cat "$cache_file" 2>/dev/null || echo "{}")
fi

json=$(
  jq -cn \
    --argjson old "$old_json" \
    --argjson cpu_usage "$usage" \
    --argjson cpu_temp "$cpu_temp" \
    --argjson cores "$cores" \
    --argjson threads "$threads" \
    --argjson threads_per_core "$threads_per_core" \
    --arg load_one "$load_1" \
    --arg load_five "$load_5" \
    --arg load_fifteen "$load_15" \
    --arg runnable "$runnable" \
    --argjson load_pct_one "$load_pct_1" \
    --argjson load_pct_five "$load_pct_5" \
    --argjson load_pct_fifteen "$load_pct_15" \
    --argjson cpu_top "$cpu_top" \
    --arg mem_used_gib "$mem_used_gib" \
    --arg mem_total_gib "$mem_total_gib" \
    --argjson mem_pct "$mem_pct" \
    --arg swap_used_gib "$swap_used_gib" \
    --arg swap_total_gib "$swap_total_gib" \
    --argjson mem_top "$mem_top" \
    --arg gpu_available "$gpu_available" \
    --arg gpu_suspended "$gpu_suspended" \
    --arg gpu_name "$gpu_name" \
    --argjson gpu_util "$gpu_util" \
    --argjson gpu_temp "$gpu_temp" \
    --argjson gpu_mem_used "$gpu_mem_used" \
    --argjson gpu_mem_total "$gpu_mem_total" \
    --argjson gpu_vram_pct "$gpu_vram_pct" \
    --argjson gpu_fan "$gpu_fan" \
    '
      ($old.cpu.history // []) as $cpu_hist |
      ($old.memory.history // []) as $mem_hist |
      (if ($cpu_hist | length) >= 10 then $cpu_hist[1:] + [$cpu_usage] else $cpu_hist + [$cpu_usage] end) as $new_cpu_hist |
      (if ($mem_hist | length) >= 10 then $mem_hist[1:] + [$mem_pct] else $mem_hist + [$mem_pct] end) as $new_mem_hist |
      {
        cpu: {
          usage: $cpu_usage,
          temp: $cpu_temp,
          topology: { cores: $cores, threads: $threads, threads_per_core: $threads_per_core },
          load: {
            one: $load_one,
            five: $load_five,
            fifteen: $load_fifteen,
            runnable: $runnable,
            pct: { one: $load_pct_one, five: $load_pct_five, fifteen: $load_pct_fifteen }
          },
          top: $cpu_top,
          history: $new_cpu_hist
        },
        memory: {
          mem_used_gib: $mem_used_gib,
          mem_total_gib: $mem_total_gib,
          mem_pct: $mem_pct,
          swap_used_gib: $swap_used_gib,
          swap_total_gib: $swap_total_gib,
          top: $mem_top,
          history: $new_mem_hist
        },
        gpu: (
          if $gpu_available == "true" then
            { available: true, name: $gpu_name, util: $gpu_util, temp: $gpu_temp,
              mem_used: $gpu_mem_used, mem_total: $gpu_mem_total, vram_pct: $gpu_vram_pct, fan: $gpu_fan,
              suspended: ($gpu_suspended == "true") }
          else
            { available: false }
          end
        )
      }
    '
  )

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
find "$cache_dir" -maxdepth 1 -name 'system-metrics.json.tmp.*' -mtime +0 -delete 2>/dev/null || true
"${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/metrics-icons-build.sh" "$cache_file" "$cache_dir/metrics-icons.json" 2>/dev/null || true
