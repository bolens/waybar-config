#!/usr/bin/env sh
# Pre-render Waybar JSON payloads for cpu/gpu/memory icon modules.
#
# Class thresholds come from settings.thresholds (same SoT as cpu-status.sh).
# Icon modules usually serve this cache; rebuilding with stale hardcodes used to
# diverge from settings (e.g. CPU temp critical 80 vs 85).
set -eu

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
# shellcheck source=waybar-locale-lib.sh
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
metrics_file="${1:-$cache_dir/system-metrics.json}"
icons_file="${2:-$cache_dir/metrics-icons.json}"
settings_file="$WAYBAR_HOME/data/waybar-settings.json"

[ -f "$metrics_file" ] || exit 0

# Defaults match data/waybar-settings.jsonc thresholds.*; override from compiled JSON.
cpu_usage_warn=60
cpu_usage_crit=85
cpu_temp_warn=75
cpu_temp_crit=85
gpu_util_warn=70
gpu_util_crit=90
gpu_temp_warn=75
gpu_temp_crit=83
mem_warn=70
mem_crit=85
if [ -f "$settings_file" ] && command -v jq >/dev/null 2>&1; then
  cpu_usage_warn=$(jq -r '.thresholds.cpu.usage.warning // 60' "$settings_file" 2>/dev/null || echo 60)
  cpu_usage_crit=$(jq -r '.thresholds.cpu.usage.critical // 85' "$settings_file" 2>/dev/null || echo 85)
  cpu_temp_warn=$(jq -r '.thresholds.cpu.temp.warning // 75' "$settings_file" 2>/dev/null || echo 75)
  cpu_temp_crit=$(jq -r '.thresholds.cpu.temp.critical // 85' "$settings_file" 2>/dev/null || echo 85)
  gpu_util_warn=$(jq -r '.thresholds.gpu.util.warning // 70' "$settings_file" 2>/dev/null || echo 70)
  gpu_util_crit=$(jq -r '.thresholds.gpu.util.critical // 90' "$settings_file" 2>/dev/null || echo 90)
  gpu_temp_warn=$(jq -r '.thresholds.gpu.temp.warning // 75' "$settings_file" 2>/dev/null || echo 75)
  gpu_temp_crit=$(jq -r '.thresholds.gpu.temp.critical // 83' "$settings_file" 2>/dev/null || echo 83)
  mem_warn=$(jq -r '.thresholds.memory.warning // 70' "$settings_file" 2>/dev/null || echo 70)
  mem_crit=$(jq -r '.thresholds.memory.critical // 85' "$settings_file" 2>/dev/null || echo 85)
fi

cpu_temp_raw="$(jq -r '.cpu.temp // 0' "$metrics_file" 2>/dev/null || echo 0)"
gpu_temp_raw="$(jq -r '.gpu.temp // 0' "$metrics_file" 2>/dev/null || echo 0)"
cpu_temp_fmt="N/A"
gpu_temp_fmt="N/A"
if [ "$cpu_temp_raw" -gt 0 ] 2>/dev/null; then
  cpu_temp_fmt=$(format_locale_temp "$cpu_temp_raw" short | tr -d '\n')
fi
if [ "$gpu_temp_raw" -gt 0 ] 2>/dev/null; then
  gpu_temp_fmt=$(format_locale_temp "$gpu_temp_raw" short | tr -d '\n')
fi

json="$(jq -cn --slurpfile m "$metrics_file" \
  --arg cpu_temp_fmt "$cpu_temp_fmt" \
  --arg gpu_temp_fmt "$gpu_temp_fmt" \
  --argjson cpu_usage_warn "$cpu_usage_warn" \
  --argjson cpu_usage_crit "$cpu_usage_crit" \
  --argjson cpu_temp_warn "$cpu_temp_warn" \
  --argjson cpu_temp_crit "$cpu_temp_crit" \
  --argjson gpu_util_warn "$gpu_util_warn" \
  --argjson gpu_util_crit "$gpu_util_crit" \
  --argjson gpu_temp_warn "$gpu_temp_warn" \
  --argjson gpu_temp_crit "$gpu_temp_crit" \
  --argjson mem_warn "$mem_warn" \
  --argjson mem_crit "$mem_crit" '
  # Right-pad usage/util so sparkline + percent stay column-aligned in the bar.
  def pad3($val): ($val | tostring) as $s | if ($s | length) == 1 then "  " + $s elif ($s | length) == 2 then " " + $s else $s end;
  # Map 0–100 history samples onto 8 block glyphs (100/8 = 12.5 per step).
  def sparkline($history):
    [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"] as $blocks |
    $history | map(
      . / 12.5 | floor | if . > 7 then 7 elif . < 0 then 0 else . end | $blocks[.]
    ) | join("");

  ($m[0]) as $metrics |
  ($metrics.cpu.usage // 0) as $usage |
  ($metrics.cpu.temp // 0) as $temp |
  ($metrics.cpu.topology.cores // 0) as $cores |
  ($metrics.cpu.topology.threads // 0) as $threads |
  ($metrics.cpu.topology.threads_per_core // 1) as $tpc |
  ($metrics.cpu.load.one // "0.00") as $l1 |
  ($metrics.cpu.load.five // "0.00") as $l5 |
  ($metrics.cpu.load.fifteen // "0.00") as $l15 |
  ($metrics.cpu.load.runnable // "0/0") as $run |
  ($metrics.cpu.load.pct.one // 0) as $lp1 |
  ($metrics.cpu.load.pct.five // 0) as $lp5 |
  ($metrics.cpu.load.pct.fifteen // 0) as $lp15 |
  ($metrics.cpu.top // []) as $cpu_top |
  ($metrics.cpu.history // []) as $cpu_hist |
  ($metrics.memory.mem_used_gib // "0.0") as $mu |
  ($metrics.memory.mem_total_gib // "0.0") as $mt |
  ($metrics.memory.mem_pct // 0) as $mp |
  ($metrics.memory.swap_used_gib // "0.0") as $su |
  ($metrics.memory.swap_total_gib // "0.0") as $st |
  ($metrics.memory.top // []) as $mem_top |
  ($metrics.memory.history // []) as $mem_hist |
  {
    cpu: {
      text: "󰍛 \(sparkline($cpu_hist)) \(pad3($usage))%",
      tooltip: (
        "CPU Utilization: \($usage)% (Temp: \($cpu_temp_fmt))\n"
        + "Topology: \($cores) cores / \($threads) threads (\($tpc)T per core)\n"
        + "Load 1m/5m/15m: \($l1) / \($l5) / \($l15)\n"
        + "Load vs thread capacity: \($lp1)% / \($lp5)% / \($lp15)%\n"
        + "Runnable tasks: \($run)\n\n"
        + "Top CPU Processes:\n"
        + ($cpu_top | map("  • " + .) | join("\n"))
      ),
      class: (
        if $usage >= $cpu_usage_crit or $temp >= $cpu_temp_crit then "critical"
        elif $usage >= $cpu_usage_warn or $temp >= $cpu_temp_warn then "warning"
        else "normal"
        end
      )
    },
    gpu: (
      if ($metrics.gpu.available // false) then
        ($metrics.gpu.name // "GPU") as $name |
        ($metrics.gpu.util // 0) as $util |
        ($metrics.gpu.temp // 0) as $temp |
        ($metrics.gpu.mem_used // 0) as $gmu |
        ($metrics.gpu.mem_total // 0) as $gmt |
        ($metrics.gpu.vram_pct // 0) as $vp |
        ($metrics.gpu.suspended // false) as $suspended |
        ($metrics.gpu.vendor // "") as $vendor |
        {
          # Idle AMD often reports util ~0 while temp is still meaningful — show temp.
          text: (
            if $vendor == "amd" and $util < 5 and $temp > 0 then
              "󰢮 \($gpu_temp_fmt)"
            else
              "󰢮 \(pad3($util))%"
            end
          ),
          tooltip: "\($name)\nUtil: \($util)%\nTemp: \($gpu_temp_fmt)\nVRAM: \($gmu)/\($gmt) MiB (\($vp)%)",
          class: (
            if $suspended then "suspended"
            elif $temp >= $gpu_temp_crit or $util >= $gpu_util_crit then "critical"
            elif $temp >= $gpu_temp_warn or $util >= $gpu_util_warn then "warning"
            else "normal"
            end
          )
        }
      else
        {
          text: "󰢮 --",
          tooltip: "GPU telemetry unavailable",
          class: "disabled"
        }
      end
    ),
    memory: {
      text: "󰘚 \(sparkline($mem_hist)) \(pad3($mp))%",
      tooltip: (
        "Memory: \($mu)/\($mt) GiB (\($mp)%)\n"
        + "Swap: \($su)/\($st) GiB\n\n"
        + "Top Memory Processes:\n"
        + ($mem_top | map("  • " + .) | join("\n"))
      ),
      class: (
        if $mp >= $mem_crit then "critical"
        elif $mp >= $mem_warn then "warning"
        else "normal"
        end
      )
    }
  }
' || echo "{}")"

tmp="$icons_file.tmp.$$"
printf '%s\n' "$json" >"$tmp"
mv -f "$tmp" "$icons_file"

# Write separate files for fast read path (bypassing jq in the widget scripts)
printf '%s\n' "$json" | jq -c '.cpu, .gpu, .memory' | {
  read -r cpu_line
  read -r gpu_line
  read -r memory_line

  [ -n "$cpu_line" ] && printf '%s\n' "$cpu_line" >"$cache_dir/cpu-icon.json.tmp.$$" && mv -f "$cache_dir/cpu-icon.json.tmp.$$" "$cache_dir/cpu-icon.json"
  [ -n "$gpu_line" ] && printf '%s\n' "$gpu_line" >"$cache_dir/gpu-icon.json.tmp.$$" && mv -f "$cache_dir/gpu-icon.json.tmp.$$" "$cache_dir/gpu-icon.json"
  [ -n "$memory_line" ] && printf '%s\n' "$memory_line" >"$cache_dir/memory-icon.json.tmp.$$" && mv -f "$cache_dir/memory-icon.json.tmp.$$" "$cache_dir/memory-icon.json"
}
