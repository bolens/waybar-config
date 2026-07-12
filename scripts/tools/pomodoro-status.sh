#!/usr/bin/env bash
# Pomodoro / focus timer status for Waybar.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
state_file="$cache_dir/pomodoro.state"
mkdir -p "$cache_dir"

work_min=$(waybar_settings_get '.pomodoro.work_min' '25')
short_min=$(waybar_settings_get '.pomodoro.short_break_min' '5')
long_min=$(waybar_settings_get '.pomodoro.long_break_min' '15')
long_every=$(waybar_settings_get '.pomodoro.long_break_every' '4')
case "$work_min" in '' | *[!0-9]*) work_min=25 ;; esac
case "$short_min" in '' | *[!0-9]*) short_min=5 ;; esac
case "$long_min" in '' | *[!0-9]*) long_min=15 ;; esac
case "$long_every" in '' | *[!0-9]*) long_every=4 ;; esac

now=$(date +%s)

if [ ! -f "$state_file" ]; then
  emit_waybar_json "󰔟" "Pomodoro idle\nLeft: start/pause · Right: reset · Middle: skip phase" "idle"
  exit 0
fi

# state: phase|ends_at|running|sessions|paused_remaining
IFS='|' read -r phase ends_at running sessions paused_remaining <"$state_file" || true
phase="${phase:-idle}"
ends_at="${ends_at:-0}"
running="${running:-0}"
sessions="${sessions:-0}"
paused_remaining="${paused_remaining:-0}"

remaining=0
if [ "$running" = "1" ]; then
  remaining=$((ends_at - now))
  if [ "$remaining" -le 0 ]; then
    # Auto-advance phase
    case "$phase" in
      work)
        sessions=$((sessions + 1))
        if [ $((sessions % long_every)) -eq 0 ]; then
          phase="long"
          dur=$((long_min * 60))
        else
          phase="short"
          dur=$((short_min * 60))
        fi
        notify-send "Pomodoro" "Work done — ${phase} break (${dur}s)" 2>/dev/null || true
        ;;
      short | long)
        phase="work"
        dur=$((work_min * 60))
        notify-send "Pomodoro" "Break over — back to work" 2>/dev/null || true
        ;;
      *)
        phase="idle"
        running=0
        dur=0
        ;;
    esac
    if [ "$phase" != "idle" ]; then
      ends_at=$((now + dur))
      running=1
      paused_remaining=0
      printf '%s|%s|%s|%s|%s\n' "$phase" "$ends_at" "$running" "$sessions" "$paused_remaining" >"$state_file"
      remaining=$dur
    else
      printf 'idle|0|0|%s|0\n' "$sessions" >"$state_file"
      emit_waybar_json "󰔟" "Pomodoro idle\nLeft: start/pause · Right: reset · Middle: skip phase" "idle"
      exit 0
    fi
  fi
elif [ "$phase" != "idle" ] && [ "$paused_remaining" -gt 0 ]; then
  remaining=$paused_remaining
else
  emit_waybar_json "󰔟" "Pomodoro idle\nSessions today: ${sessions}\nLeft: start/pause · Right: reset · Middle: skip phase" "idle"
  exit 0
fi

mins=$((remaining / 60))
secs=$((remaining % 60))
time_fmt=$(printf '%d:%02d' "$mins" "$secs")

case "$phase" in
  work)
    icon="󰔟"
    label="Focus"
    class="work"
    ;;
  short)
    icon="󰒲"
    label="Short break"
    class="break"
    ;;
  long)
    icon="󰒲"
    label="Long break"
    class="break"
    ;;
  *)
    icon="󰔟"
    label="Pomodoro"
    class="idle"
    ;;
esac

status="running"
[ "$running" = "1" ] || status="paused"

emit_waybar_json "${icon} ${time_fmt}" \
  "${label} (${status})\nRemaining: ${time_fmt}\nCompleted sessions: ${sessions}\nLeft: pause/resume · Right: reset · Middle: skip" \
  "$class"
