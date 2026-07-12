#!/usr/bin/env bash
# Shared CPU / memory / GPU metrics for Waybar (one refresh serves all monitors).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/system-metrics-cpu.sh"
. "$WAYBAR_SCRIPTS/lib/system-metrics-gpu.sh"
. "$WAYBAR_SCRIPTS/lib/system-metrics-top.sh"
cache_file="$cache_dir/system-metrics.json"
lock_dir="$cache_dir/system-metrics.lock.d"
stat_prev="$cache_dir/cpu-stat.prev"
topology_file="$cache_dir/cpu-topology.json"

ttl="$(waybar_module_interval cpu 8)"
# Topology (cores/threads) almost never changes — cache for a day.
topology_ttl=86400
stale_lock_ttl=30

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
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

# Test/portability hooks: override sysfs roots for CI fixtures without touching host.
# Path discovery still caches under $XDG_CACHE_HOME/waybar/*-path.txt — clear those
# when swapping WAYBAR_HWMON_ROOT / WAYBAR_THERMAL_ROOT between test cases.
hwmon_root="${WAYBAR_HWMON_ROOT:-/sys/class/hwmon}"
thermal_root="${WAYBAR_THERMAL_ROOT:-/sys/class/thermal}"

ensure_topology_file
read -r cores threads threads_per_core <<EOF
$(jq -r '[.cores // 1, .threads // 1, .threads_per_core // 1] | @tsv' "$topology_file")
EOF

usage="$(compute_cpu_usage_percent)"
cpu_temp="$(read_cpu_temperature)"

# Read load average directly using shell builtin
read -r load_1 load_5 load_15 runnable _ </proc/loadavg

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

# Word-split whitespace fields from awk (quoted read avoids SC2086).
# shellcheck disable=SC2086
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
gpu_vendor=""
gpu_util=0
gpu_temp=0
gpu_mem_used=0
gpu_mem_total=0
gpu_vram_pct=0
gpu_fan=0

gpu_path_file="$cache_dir/gpu-pci-path.txt"
amd_hwmon_file="$cache_dir/amdgpu-hwmon-path.txt"

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
      printf '%s' "$gpu_dev" >"$tmp_gpu_path"
      mv -f "$tmp_gpu_path" "$gpu_path_file"
    else
      tmp_gpu_path="$gpu_path_file.tmp.$$"
      printf '' >"$tmp_gpu_path"
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
    # Prefer AMD iGPU telemetry while the dGPU sleeps (no nvidia-smi wake).
    if ! fill_amdgpu_metrics; then
      gpu_available="true"
      gpu_vendor="nvidia"
      gpu_name="NVIDIA GPU"
      if [ -f "$cache_file" ]; then
        gpu_name=$(jq -r '.gpu.name // "NVIDIA GPU"' "$cache_file" 2>/dev/null || echo "NVIDIA GPU")
        gpu_name="${gpu_name% (Suspended)}"
        gpu_name="${gpu_name%% @*}"
      fi
      gpu_name="$gpu_name (Suspended)"
    fi
  else
    line=$(timeout 2 nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,fan.speed --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)
    if [ -n "$line" ]; then
      gpu_available="true"
      gpu_vendor="nvidia"
      tab=$(printf '\t')
      gpu_fields=$(printf '%s\n' "$line" | awk -F', *' -v OFS='\t' '{
        gsub(/^ +| +$/,"", $1);
        print $1, int($2), int($3), int($4), int($5), int($6)
      }')

      old_ifs=$IFS
      IFS=$tab
      # shellcheck disable=SC2086 # intentional split of tab-separated nvidia-smi fields
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

# No usable NVIDIA path → AMD iGPU / dGPU via amdgpu hwmon
if [ "$gpu_available" != "true" ]; then
  fill_amdgpu_metrics || true
fi

cpu_top="[]"
mem_top="[]"
refresh_process_tops

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
    --arg gpu_vendor "$gpu_vendor" \
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
            { available: true, name: $gpu_name, vendor: $gpu_vendor, util: $gpu_util, temp: $gpu_temp,
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
"$WAYBAR_SCRIPTS/infra/metrics-icons-build.sh" "$cache_file" "$cache_dir/metrics-icons.json" 2>/dev/null || true
