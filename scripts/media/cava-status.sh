#!/usr/bin/env bash
# Continuous cava bars for Waybar. Emits empty + hidden when cava missing or silent.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

bars=$(waybar_settings_get '.cava.bars' '8')
framerate=$(waybar_settings_get '.cava.framerate' '30')
case "$bars" in '' | *[!0-9]*) bars=8 ;; esac
case "$framerate" in '' | *[!0-9]*) framerate=30 ;; esac
if [ "$bars" -lt 4 ]; then bars=4; fi
if [ "$bars" -gt 32 ]; then bars=32; fi
# Cap engine rate — high framerate × dual outputs floods Waybar and kills tooltips.
if [ "$framerate" -gt 12 ]; then framerate=12; fi

cava_bin="${WAYBAR_CAVA_BIN:-cava}"

emit_hidden() {
  emit_waybar_json "" "Audio visualizer (cava)\nInstall cava to enable" "hidden"
}

if ! command -v "$cava_bin" >/dev/null 2>&1; then
  emit_hidden
  # Infinite sleep keeps the custom module process alive so Waybar does not
  # restart-spam when cava is not installed; wake only on bar reload.
  while true; do sleep 3600; done
fi

cfg=$(mktemp "${TMPDIR:-/tmp}/waybar-cava.XXXXXX")
fifo=$(mktemp -u "${TMPDIR:-/tmp}/waybar-cava-fifo.XXXXXX")
mkfifo "$fifo"
cleanup() {
  rm -f "$cfg" "$fifo"
  [ -n "${cava_pid:-}" ] && kill "$cava_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cat >"$cfg" <<EOF
[general]
bars = $bars
framerate = $framerate
[output]
method = raw
raw_target = $fifo
data_format = ascii
# Index into ▁▂▃▄▅▆▇█ (0–7); full loudness uses █ unlike gauge_bar's ▇ max.
ascii_max_range = 7
EOF

"$cava_bin" -p "$cfg" >/dev/null 2>&1 &
cava_pid=$!

# ▁▂▃▄▅▆▇█
dict="▁▂▃▄▅▆▇█"
silent_streak=0
# Cap Waybar JSON updates — continuous cava frames starve the GTK loop and kill
# tooltips bar-wide (see Alexays/Waybar#3910 / #4909 / #3356).
emit_min_ms=800
last_emit_ms=0
last_payload=""

while IFS= read -r line; do
  [ -n "$line" ] || continue
  # cava ascii: semicolon-separated 0-7
  out=""
  all_zero=1
  IFS=';' read -r -a vals <<<"$line"
  for v in "${vals[@]}"; do
    case "$v" in '' | *[!0-9]*) v=0 ;; esac
    if [ "$v" -gt 7 ]; then v=7; fi
    if [ "$v" -gt 0 ]; then all_zero=0; fi
    # bash substring is 0-based; dict chars are 0-7
    out="${out}${dict:v:1}"
  done

  now_ms=$(date +%s%3N 2>/dev/null || echo 0)
  case "$now_ms" in '' | *[!0-9]*) now_ms=0 ;; esac
  if [ "$now_ms" -gt 0 ] && [ "$last_emit_ms" -gt 0 ] \
    && [ $((now_ms - last_emit_ms)) -lt "$emit_min_ms" ]; then
    continue
  fi

  if [ "$all_zero" -eq 1 ]; then
    silent_streak=$((silent_streak + 1))
    # ~8 silent frames at configured framerate before hiding the module.
    if [ "$silent_streak" -ge 8 ]; then
      payload='hidden'
      if [ "$payload" = "$last_payload" ]; then
        continue
      fi
      last_payload="$payload"
      [ "$now_ms" -gt 0 ] && last_emit_ms=$now_ms
      emit_waybar_json "" "Cava (silent)" "hidden"
      continue
    fi
  else
    silent_streak=0
  fi

  payload="bars:$out"
  if [ "$payload" = "$last_payload" ]; then
    continue
  fi
  last_payload="$payload"
  [ "$now_ms" -gt 0 ] && last_emit_ms=$now_ms
  emit_waybar_json "$out" "Audio visualizer" "normal"
done <"$fifo"
