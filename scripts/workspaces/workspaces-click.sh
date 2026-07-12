#!/usr/bin/env bash
# Click/scroll actions for workspace strip modules.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=output-lib.sh
. "$WAYBAR_SCRIPTS/lib/output-lib.sh"

comp="$(detect_compositor)"
action="${1:-}"
output="${2:-${WAYBAR_OUTPUT_NAME:-}}"

case "$action" in
  scroll-up | scroll-down)
    per_output=0
    if waybar_scroll_per_output_enabled && [ -n "$output" ]; then
      per_output=1
    fi

    case "$comp" in
      kde)
        if [ "$per_output" -eq 1 ]; then
          python3 "$script_dir/workspaces-click.py" "$action" "$output" || true
        else
          if [ "$action" = "scroll-up" ]; then
            command -v qdbus6 >/dev/null 2>&1 \
              && timeout 2 qdbus6 org.kde.KWin /KWin org.kde.KWin.previousDesktop >/dev/null 2>&1 \
              || true
          else
            command -v qdbus6 >/dev/null 2>&1 \
              && timeout 2 qdbus6 org.kde.KWin /KWin org.kde.KWin.nextDesktop >/dev/null 2>&1 \
              || true
          fi
        fi
        ;;
      hyprland)
        if [ "$per_output" -eq 1 ]; then
          hyprctl dispatch focusmonitor "$output" >/dev/null 2>&1 || true
        fi
        if [ "$action" = "scroll-up" ]; then
          hyprctl dispatch workspace e-1 >/dev/null 2>&1 || true
        else
          hyprctl dispatch workspace e+1 >/dev/null 2>&1 || true
        fi
        ;;
    esac
    ;;
  [0-9] | [1-9][0-9])
    python3 "$script_dir/workspaces-click.py" "$action" "${output}" || true
    ;;
  *)
    exit 0
    ;;
esac

# Invalidate cache to force instant redraw of active indicator on click/scroll
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar"/workspaces-*.json 2>/dev/null || true
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" 16
