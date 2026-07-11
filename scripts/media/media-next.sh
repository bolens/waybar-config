#!/usr/bin/env sh
set -eu
status=$(playerctl status 2>/dev/null || echo "NoPlayer")
case "$status" in
  Playing) class="playing" ;;
  Paused) class="paused" ;;
  *) class="stopped" ;;
esac
printf '{"text":"󰒭","class":"%s"}\n' "$class"
