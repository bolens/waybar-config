#!/usr/bin/env bash
# GPU (NVIDIA / AMD) helpers for system-metrics-collector.
# Expected caller context: cache_dir, gpu_* vars, hwmon_root, gpu_path_file, amd_hwmon_file, cache_file.
# shellcheck disable=SC2154 # variables provided by system-metrics-collector.sh

find_gpu_path() {
  for dev in /sys/bus/pci/devices/*; do
    if [ -f "$dev/vendor" ] && [ "$(cat "$dev/vendor")" = "0x10de" ]; then
      printf '%s' "$dev"
      return 0
    fi
  done
  return 1
}
find_amdgpu_hwmon() {
  local d name
  if [ -f "$amd_hwmon_file" ]; then
    d=$(cat "$amd_hwmon_file" 2>/dev/null || true)
    if [ -n "$d" ] && [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "amdgpu" ]; then
      printf '%s' "$d"
      return 0
    fi
  fi
  for d in "$hwmon_root"/hwmon*; do
    [ -f "$d/name" ] || continue
    name=$(cat "$d/name" 2>/dev/null || true)
    if [ "$name" = "amdgpu" ]; then
      printf '%s' "$d" >"$amd_hwmon_file.tmp.$$" 2>/dev/null && mv -f "$amd_hwmon_file.tmp.$$" "$amd_hwmon_file" 2>/dev/null || true
      printf '%s' "$d"
      return 0
    fi
  done
  return 1
}
fill_amdgpu_metrics() {
  local hwmon card_dev freq_hz vram_total vram_used
  hwmon=$(find_amdgpu_hwmon || true)
  [ -n "$hwmon" ] || return 1

  gpu_available="true"
  gpu_vendor="amd"
  gpu_suspended="false"
  gpu_fan=0
  gpu_util=0
  gpu_name="AMD GPU"
  if [ -f "$hwmon/device/../../vendor" ] || [ -e "$hwmon/device" ]; then
    card_dev=$(readlink -f "$hwmon/device" 2>/dev/null || true)
    if [ -n "$card_dev" ] && [ -f "$card_dev/mem_info_vram_total" ]; then
      vram_total=$(cat "$card_dev/mem_info_vram_total" 2>/dev/null || echo 0)
      vram_used=$(cat "$card_dev/mem_info_vram_used" 2>/dev/null || echo 0)
      if [ "${vram_total:-0}" -gt 0 ] 2>/dev/null; then
        gpu_mem_total=$((vram_total / 1024 / 1024))
        gpu_mem_used=$((vram_used / 1024 / 1024))
        gpu_vram_pct=$((gpu_mem_used * 100 / gpu_mem_total))
      fi
    fi
    # Pretty name from DRM product if present
    if [ -n "$card_dev" ] && [ -f "$card_dev/product_name" ]; then
      gpu_name=$(tr -d '\n' <"$card_dev/product_name" 2>/dev/null || echo "AMD GPU")
    elif [ -n "$card_dev" ] && [ -f "$card_dev/label" ]; then
      gpu_name=$(tr -d '\n' <"$card_dev/label" 2>/dev/null || echo "AMD GPU")
    else
      gpu_name="AMD iGPU"
    fi
  fi

  if [ -f "$hwmon/temp1_input" ]; then
    gpu_temp=$(($(cat "$hwmon/temp1_input") / 1000))
  fi
  # amdgpu rarely exposes busy % via hwmon; leave util at 0 (UI shows temp instead).
  gpu_util=0
  if [ -f "$hwmon/freq1_input" ]; then
    freq_hz=$(cat "$hwmon/freq1_input" 2>/dev/null || echo 0)
    if [ "${freq_hz:-0}" -gt 0 ] 2>/dev/null; then
      gpu_name=$(printf '%s @ %d MHz' "$gpu_name" $((freq_hz / 1000000)))
    fi
  fi
  return 0
}
