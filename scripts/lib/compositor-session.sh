#!/usr/bin/env sh
# Shared compositor detection for Waybar scripts (KDE Plasma + Hyprland).

detect_compositor() {
  # Session-scoped cache avoids repeated pgrep when env is thin.
  _wb_comp_cache="${XDG_RUNTIME_DIR:-/tmp}/waybar-compositor"
  if [ -n "${WAYBAR_COMPOSITOR:-}" ]; then
    printf '%s\n' "$WAYBAR_COMPOSITOR"
    return 0
  fi
  if [ -f "$_wb_comp_cache" ]; then
    _wb_cached="$(cat "$_wb_comp_cache" 2>/dev/null || true)"
    case "$_wb_cached" in
      hyprland|kde|unknown)
        printf '%s\n' "$_wb_cached"
        return 0
        ;;
    esac
  fi

  _wb_comp="unknown"
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    _wb_comp="hyprland"
  else
    desktop="${XDG_CURRENT_DESKTOP:-}${XDG_SESSION_DESKTOP:-}${DESKTOP_SESSION:-}"
    case "$desktop" in
      *Hyprland*|*hyprland*) _wb_comp="hyprland" ;;
      *KDE*|*Plasma*|*plasma*) _wb_comp="kde" ;;
    esac

    if [ "$_wb_comp" = "unknown" ] && [ -n "${KDE_SESSION_VERSION:-}" ]; then
      _wb_comp="kde"
    fi

    if [ "$_wb_comp" = "unknown" ]; then
      if pgrep -x kwin_wayland >/dev/null 2>&1 || pgrep -x kwin_x11 >/dev/null 2>&1; then
        _wb_comp="kde"
      elif pgrep -x Hyprland >/dev/null 2>&1 || pgrep -x hyprland >/dev/null 2>&1; then
        _wb_comp="hyprland"
      fi
    fi
  fi

  # Best-effort cache; ignore failures in restricted environments.
  if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
    printf '%s\n' "$_wb_comp" >"$_wb_comp_cache" 2>/dev/null || true
  fi
  printf '%s\n' "$_wb_comp"
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

