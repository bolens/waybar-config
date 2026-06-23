#!/usr/bin/env sh
# Click/scroll actions for workspace strip modules.
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

comp="$(detect_compositor)"
action="${1:-}"

case "$action" in
  scroll-up)
    case "$comp" in
      kde)
        command -v qdbus6 >/dev/null 2>&1 \
          && timeout 2 qdbus6 org.kde.KWin /KWin org.kde.KWin.previousDesktop >/dev/null 2>&1 \
          || true
        ;;
      hyprland)
        hyprctl dispatch workspace e-1 >/dev/null 2>&1 || true
        ;;
    esac
    ;;
  scroll-down)
    case "$comp" in
      kde)
        command -v qdbus6 >/dev/null 2>&1 \
          && timeout 2 qdbus6 org.kde.KWin /KWin org.kde.KWin.nextDesktop >/dev/null 2>&1 \
          || true
        ;;
      hyprland)
        hyprctl dispatch workspace e+1 >/dev/null 2>&1 || true
        ;;
    esac
    ;;
  [0-9]|[1-9][0-9])
    python3 "$script_dir/workspaces-click.py" "$action" "${2:-}" || true
    ;;
  *)
    exit 0
    ;;
esac

# Invalidate cache to force instant redraw of active indicator on click/scroll
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar"/workspaces-*.json 2>/dev/null || true
"$script_dir/waybar-signal.sh" 16
