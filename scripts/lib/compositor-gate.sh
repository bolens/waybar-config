#!/usr/bin/env sh
# Run a module status command only on matching compositors (KDE + Hyprland dual support).
set -eu

script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

show_for=""
hide_for=""

usage() {
  printf 'Usage: %s [--show kde|hyprland] [--hide kde|hyprland] -- <command...>\n' "$0" >&2
}

hidden_json() {
  emit_waybar_json "" "" "hidden"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --show)
      show_for="${2:-}"
      shift 2
      ;;
    --hide)
      hide_for="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

comp="$(detect_compositor)"

if [ -n "$show_for" ] && [ "$comp" != "$show_for" ]; then
  hidden_json
  exit 0
fi

if [ -n "$hide_for" ] && [ "$comp" = "$hide_for" ]; then
  hidden_json
  exit 0
fi

exec "$@"
