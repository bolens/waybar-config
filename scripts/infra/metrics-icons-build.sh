#!/usr/bin/env sh
# Pre-render Waybar JSON payloads for cpu/gpu/memory icon modules.
set -eu

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
# shellcheck source=waybar-locale-lib.sh
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
metrics_file="${1:-$cache_dir/system-metrics.json}"
icons_file="${2:-$cache_dir/metrics-icons.json}"

[ -f "$metrics_file" ] || exit 0

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
  --arg gpu_temp_fmt "$gpu_temp_fmt" '
  def pad3($val): ($val | tostring) as $s | if ($s | length) == 1 then "  " + $s elif ($s | length) == 2 then " " + $s else $s end;
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
        if $usage >= 85 or $temp >= 80 then "critical"
        elif $usage >= 60 or $temp >= 70 then "warning"
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
            elif $temp >= 83 or $util >= 90 then "critical"
            elif $temp >= 75 or $util >= 70 then "warning"
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
        if $mp >= 85 then "critical"
        elif $mp >= 70 then "warning"
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
