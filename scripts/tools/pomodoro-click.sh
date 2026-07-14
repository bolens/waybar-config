#!/usr/bin/env bash
# Pomodoro controls: toggle | reset | skip
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

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

action="${1:-toggle}"
now=$(date +%s)

phase=idle
ends_at=0
running=0
sessions=0
paused_remaining=0
if [ -f "$state_file" ]; then
  IFS='|' read -r phase ends_at running sessions paused_remaining <"$state_file" || true
  phase="${phase:-idle}"
  ends_at="${ends_at:-0}"
  running="${running:-0}"
  sessions="${sessions:-0}"
  paused_remaining="${paused_remaining:-0}"
fi

write_state() {
  printf '%s|%s|%s|%s|%s\n' "$phase" "$ends_at" "$running" "$sessions" "$paused_remaining" >"$state_file"
}

phase_duration() {
  case "$1" in
    work) echo $((work_min * 60)) ;;
    short) echo $((short_min * 60)) ;;
    long) echo $((long_min * 60)) ;;
    *) echo $((work_min * 60)) ;;
  esac
}

case "$action" in
  toggle)
    if [ "$phase" = "idle" ]; then
      phase="work"
      running=1
      paused_remaining=0
      ends_at=$((now + $(phase_duration work)))
    elif [ "$running" = "1" ]; then
      remaining=$((ends_at - now))
      [ "$remaining" -lt 0 ] && remaining=0
      paused_remaining=$remaining
      running=0
      ends_at=0
    else
      running=1
      ends_at=$((now + paused_remaining))
      paused_remaining=0
    fi
    write_state
    ;;
  reset)
    rm -f "$state_file"
    ;;
  skip)
    case "$phase" in
      work)
        sessions=$((sessions + 1))
        if [ $((sessions % long_every)) -eq 0 ]; then
          phase="long"
        else
          phase="short"
        fi
        ;;
      short | long)
        phase="work"
        ;;
      *)
        phase="work"
        ;;
    esac
    running=1
    paused_remaining=0
    ends_at=$((now + $(phase_duration "$phase")))
    write_state
    ;;
  *)
    echo "Usage: $0 {toggle|reset|skip}" >&2
    exit 1
    ;;
esac

if [ -x "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" ]; then
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" pomodoro 2>/dev/null || true
fi
