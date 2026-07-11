#!/usr/bin/env sh
# Shared compositor detection for Waybar scripts (KDE Plasma + Hyprland).

detect_compositor() {
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    printf 'hyprland\n'
    return 0
  fi

  desktop="${XDG_CURRENT_DESKTOP:-}${XDG_SESSION_DESKTOP:-}${DESKTOP_SESSION:-}"
  case "$desktop" in
    *Hyprland*|*hyprland*)
      printf 'hyprland\n'
      return 0
      ;;
    *KDE*|*Plasma*|*plasma*)
      printf 'kde\n'
      return 0
      ;;
  esac

  if [ -n "${KDE_SESSION_VERSION:-}" ]; then
    printf 'kde\n'
    return 0
  fi

  if pgrep -x kwin_wayland >/dev/null 2>&1 || pgrep -x kwin_x11 >/dev/null 2>&1; then
    printf 'kde\n'
    return 0
  fi

  if pgrep -x Hyprland >/dev/null 2>&1 || pgrep -x hyprland >/dev/null 2>&1; then
    printf 'hyprland\n'
    return 0
  fi

  printf 'unknown\n'
}

_pick_terminal() {
  compositor="$1"
  case "$compositor" in
    hyprland) order="foot kitty ghostty alacritty konsole xterm" ;;
    kde)      order="konsole kitty ghostty foot alacritty xterm" ;;
    *)        order="kitty foot ghostty konsole alacritty xterm" ;;
  esac
  for term in $order; do
    command -v "$term" >/dev/null 2>&1 && { printf '%s' "$term"; return 0; }
  done
  return 1
}

_run_in_terminal() {
  term="$1"; shift
  case "$term" in
    foot|alacritty|kitty|ghostty) "$term" -- "$@" & ;;
    *) "$term" -e "$@" & ;;
  esac
}

