#!/usr/bin/env sh
# shellcheck disable=SC2154 # brightness_cache_file assigned in brightness-lib.sh (ShellCheck misses top-level assigns there)
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
mode="${1:-adjust}"
value="${2:-+5}"
# Optional third arg or WAYBAR_OUTPUT_NAME selects the display when brightness.per_output.
out_name="${3:-${WAYBAR_OUTPUT_NAME:-}}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
state_file="$cache_dir/brightness-ddc-displays"

# shellcheck source=../lib/brightness-lib.sh
. "$WAYBAR_SCRIPTS/lib/brightness-lib.sh"
# shellcheck source=ddcutil-lock.sh
. "$WAYBAR_SCRIPTS/lib/ddcutil-lock.sh"

brightness_bind_output "$out_name"
BRIGHTNESS_TARGET=$(brightness_resolve_target "$out_name")

if [ -n "${BRIGHTNESS_OUTPUT_SAFE:-}" ]; then
  pending_adjust_file="$cache_dir/brightness-pending-adjust-${BRIGHTNESS_OUTPUT_SAFE}"
  pending_set_file="$cache_dir/brightness-pending-set-${BRIGHTNESS_OUTPUT_SAFE}"
  queue_lock_dir="$cache_dir/brightness-queue-${BRIGHTNESS_OUTPUT_SAFE}.lock"
  worker_lock_dir="$cache_dir/brightness-worker-${BRIGHTNESS_OUTPUT_SAFE}.lock"
else
  pending_adjust_file="$cache_dir/brightness-pending-adjust"
  pending_set_file="$cache_dir/brightness-pending-set"
  queue_lock_dir="$cache_dir/brightness-queue.lock"
  worker_lock_dir="$cache_dir/brightness-worker.lock"
fi

mkdir -p "$cache_dir"

clamp() {
  val="$1"
  if [ "$val" -lt 1 ]; then
    printf '1\n'
  elif [ "$val" -gt 100 ]; then
    printf '100\n'
  else
    printf '%s\n' "$val"
  fi
}

refresh_waybar() {
  rm -f "$brightness_cache_file" 2>/dev/null || true
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" brightness
}

# with_queue_lock:
# Basic directory-creation mutex. mkdir is atomic in POSIX filesystems.
# We retry up to 200 times with a 10ms delay (total 2 seconds max wait time).
with_queue_lock() {
  attempts=0
  while ! mkdir "$queue_lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "$attempts" -ge 200 ] && return 1
    sleep 0.01
  done

  "$@"
  status=$?
  rmdir "$queue_lock_dir" 2>/dev/null || true
  return "$status"
}

# enqueue_request:
# Rapid mouse scrolling on the status icon produces a burst of script executions.
# Instead of launching concurrent hardware queries (which lag or crash), we aggregate
# relative adjustments (+5, -5) or set values (80) into a single pending status file.
enqueue_request() {
  case "$mode" in
    adjust)
      sign=$(printf '%s' "$value" | cut -c1)
      amount=$(printf '%s' "$value" | tr -d '+-')
      pending=0
      if [ -f "$pending_adjust_file" ]; then
        pending=$(cat "$pending_adjust_file" 2>/dev/null || printf '0\n')
      fi
      if [ "$sign" = "-" ]; then
        pending=$((pending - amount))
      else
        pending=$((pending + amount))
      fi
      printf '%s\n' "$pending" >"$pending_adjust_file"
      ;;
    set)
      target=$(clamp "$value")
      printf '%s\n' "$target" >"$pending_set_file"
      rm -f "$pending_adjust_file"
      ;;
  esac
}

# drain_request:
# Read the aggregated adjustment/setting values and clear the pending status files.
drain_request() {
  request_mode=""
  request_value=""

  if [ -f "$pending_set_file" ]; then
    request_mode="set"
    request_value=$(cat "$pending_set_file" 2>/dev/null || true)
    rm -f "$pending_set_file" "$pending_adjust_file"
    return 0
  fi

  if [ -f "$pending_adjust_file" ]; then
    request_value=$(cat "$pending_adjust_file" 2>/dev/null || true)
    rm -f "$pending_adjust_file"
    if [ -n "$request_value" ] && [ "$request_value" != "0" ]; then
      request_mode="adjust"
    fi
  fi
}

# apply_backlight:
# Attempts to write to internal laptop backlight controls using brightnessctl.
# If no backlight interfaces are found, returns 1 to trigger DDC fallbacks.
apply_backlight() {
  bl_dev=""
  case "${BRIGHTNESS_TARGET:-}" in
    backlight:*) bl_dev="${BRIGHTNESS_TARGET#backlight:}" ;;
    backlight) bl_dev="" ;;
    ddc:*) return 1 ;;
  esac

  if [ -n "$bl_dev" ]; then
    backlights=$(brightnessctl --class=backlight -d "$bl_dev" -m 2>/dev/null || true)
  else
    backlights=$(brightnessctl --class=backlight -m 2>/dev/null || true)
  fi
  [ -n "$backlights" ] || return 1
  case "$mode" in
    adjust)
      delta="$value"
      case "$delta" in
        -* | +*) ;;
        *) delta="+$delta" ;;
      esac
      if [ -n "$bl_dev" ]; then
        brightnessctl --class=backlight -d "$bl_dev" set "${delta}%" >/dev/null 2>&1
      else
        brightnessctl --class=backlight set "${delta}%" >/dev/null 2>&1
      fi
      ;;
    set)
      target=$(clamp "$value")
      if [ -n "$bl_dev" ]; then
        brightnessctl --class=backlight -d "$bl_dev" set "${target}%" >/dev/null 2>&1
      else
        brightnessctl --class=backlight set "${target}%" >/dev/null 2>&1
      fi
      ;;
  esac
}

# apply_ddc:
# Queries or updates brightness on external monitors via DDC/CI (I2C interface).
# MCCS VCP (Virtual Control Panel) Code 10 is the VESA standard for brightness control.
apply_ddc() {
  command -v ddcutil >/dev/null 2>&1 || return 1

  display_ids=""
  case "${BRIGHTNESS_TARGET:-}" in
    ddc:*)
      display_ids="${BRIGHTNESS_TARGET#ddc:}"
      ;;
    *)
      if [ -f "$state_file" ]; then
        display_ids=$(cat "$state_file")
      fi
      if [ -z "$display_ids" ]; then
        display_ids=$(with_ddcutil_lock ddcutil detect --brief 2>/dev/null | sed -n 's/^Display \([0-9][0-9]*\)$/\1/p' | xargs 2>/dev/null || true)
      fi
      ;;
  esac
  [ -n "$display_ids" ] || return 1

  for display_id in $display_ids; do
    # VCP 10 gets brightness. The brief output format is: "VCP 10 CNC <current_value> <max_value>"
    line=$(with_ddcutil_lock ddcutil getvcp 10 --brief --display "$display_id" 2>/dev/null | tail -n1 || true)
    case "$line" in
      "VCP 10"*)
        current=$(printf '%s\n' "$line" | awk '{print $(NF-1)}')
        max=$(printf '%s\n' "$line" | awk '{print $NF}')
        [ "$max" -gt 0 ] 2>/dev/null || continue
        current_pct=$((current * 100 / max))
        case "$mode" in
          adjust)
            sign=$(printf '%s' "$value" | cut -c1)
            amount=$(printf '%s' "$value" | tr -d '+-')
            target_pct=$current_pct
            if [ "$sign" = "-" ]; then
              target_pct=$((current_pct - amount))
            else
              target_pct=$((current_pct + amount))
            fi
            ;;
          set)
            target_pct="$value"
            ;;
        esac
        target_pct=$(clamp "$target_pct")
        target=$((target_pct * max / 100))
        if [ "$target" -lt 1 ]; then
          target=1
        fi
        with_ddcutil_lock ddcutil setvcp 10 "$target" --display "$display_id" >/dev/null 2>&1 || true
        ;;
    esac
  done
}

# start_worker:
# Background worker loop that continuously drains pending requests.
# The sleep 0.05 enforces a minimal interval between VCP writes to match hardware refresh limits.
start_worker() {
  (
    sleep 0.12
    while :; do
      with_queue_lock drain_request || exit 0

      if [ -z "$request_mode" ] || [ -z "$request_value" ]; then
        with_queue_lock rmdir "$worker_lock_dir" 2>/dev/null || true
        exit 0
      fi

      mode="$request_mode"
      value="$request_value"

      case "${BRIGHTNESS_TARGET:-legacy}" in
        ddc:*)
          apply_ddc || true
          ;;
        backlight | backlight:*)
          if ! apply_backlight; then
            apply_ddc || true
          fi
          ;;
        *)
          if ! apply_backlight; then
            apply_ddc || true
          fi
          ;;
      esac

      refresh_waybar

      sleep 0.05
    done
  ) >/dev/null 2>&1 &
}

with_queue_lock enqueue_request || exit 0

if mkdir "$worker_lock_dir" 2>/dev/null; then
  start_worker
fi

exit 0
