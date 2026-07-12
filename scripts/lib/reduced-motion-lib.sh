#!/usr/bin/env sh
# Detect desktop/compositor "reduce motion" preferences for Waybar.
# GTK3 CssProvider does not support @media (prefers-reduced-motion), so we probe
# GNOME / Plasma / Hyprland and bake an override CSS file instead.
#
# Settings: visual.animations.reduced_motion = auto | force | off  (default: auto)
# Env override: WAYBAR_REDUCED_MOTION=1|0|true|false|on|off
#
# Can be sourced from bash or dash. Apply helper: waybar_apply_reduced_motion_css

waybar_reduced_motion_mode() {
  if command -v waybar_settings_get >/dev/null 2>&1; then
    waybar_settings_get '.visual.animations.reduced_motion' 'auto'
    return 0
  fi
  _wb_rm_settings="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/waybar-settings.json"
  if [ -f "$_wb_rm_settings" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.visual.animations.reduced_motion // "auto"' "$_wb_rm_settings" 2>/dev/null || printf 'auto'
    return 0
  fi
  printf 'auto'
}

waybar_reduced_motion_env_override() {
  case "${WAYBAR_REDUCED_MOTION:-}" in
    1 | true | TRUE | yes | YES | on | ON | reduce) printf '1' ;;
    0 | false | FALSE | no | NO | off | OFF) printf '0' ;;
    *) printf '' ;;
  esac
}

waybar_probe_gnome_reduced_motion() {
  command -v gsettings >/dev/null 2>&1 || return 1
  _wb_rm="$(gsettings get org.gnome.desktop.a11y.interface reduced-motion 2>/dev/null || true)"
  case "$_wb_rm" in
    *\'reduce\'* | *\"reduce\"* | reduce) return 0 ;;
  esac
  _wb_anim="$(gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null || true)"
  case "$_wb_anim" in
    false | False | FALSE) return 0 ;;
  esac
  return 1
}

waybar_probe_plasma_reduced_motion() {
  # Plasma "Animation speed → Instant" sets AnimationDurationFactor to 0.
  _wb_factor=""
  if command -v kreadconfig6 >/dev/null 2>&1; then
    _wb_factor="$(kreadconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 2>/dev/null || true)"
    [ -n "$_wb_factor" ] || _wb_factor="$(kreadconfig6 --file kwinrc --group KDE --key AnimationDurationFactor 2>/dev/null || true)"
  elif command -v kreadconfig5 >/dev/null 2>&1; then
    _wb_factor="$(kreadconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor 2>/dev/null || true)"
  fi
  if [ -z "$_wb_factor" ]; then
    for _wb_f in "${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals" "${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc"; do
      [ -f "$_wb_f" ] || continue
      _wb_line="$(awk -F= '/^AnimationDurationFactor=/{print $2; exit}' "$_wb_f" 2>/dev/null || true)"
      if [ -n "$_wb_line" ]; then
        _wb_factor="$_wb_line"
        break
      fi
    done
  fi
  [ -n "$_wb_factor" ] || return 1
  awk -v f="$_wb_factor" 'BEGIN { exit (f+0 <= 0) ? 0 : 1 }'
}

waybar_probe_hyprland_reduced_motion() {
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  _wb_raw="$(hyprctl getoption animations:enabled -j 2>/dev/null || true)"
  [ -n "$_wb_raw" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$_wb_raw" | jq -e '
      ((.int // 1) | tonumber) == 0
      or (.set == false)
      or ((.str // "") | test("^(0|false|no|off)$"; "i"))
    ' >/dev/null 2>&1
    return $?
  fi
  printf '%s' "$_wb_raw" | grep -Eqi '"int"[[:space:]]*:[[:space:]]*0'
}

# Exit 0 when Waybar should suppress motion; print source on stdout when active.
waybar_reduced_motion_active() {
  _wb_override="$(waybar_reduced_motion_env_override)"
  if [ "$_wb_override" = "1" ]; then
    printf 'env'
    return 0
  fi
  if [ "$_wb_override" = "0" ]; then
    return 1
  fi

  _wb_mode="$(waybar_reduced_motion_mode | tr '[:upper:]' '[:lower:]')"
  case "$_wb_mode" in
    force | always | on | true | 1)
      printf 'settings:force'
      return 0
      ;;
    off | never | false | 0)
      return 1
      ;;
  esac

  if waybar_probe_gnome_reduced_motion; then
    printf 'gnome'
    return 0
  fi
  if waybar_probe_plasma_reduced_motion; then
    printf 'plasma'
    return 0
  fi
  if waybar_probe_hyprland_reduced_motion; then
    printf 'hyprland'
    return 0
  fi
  return 1
}

waybar_apply_reduced_motion_css() {
  _wb_home="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
  _wb_out="$_wb_home/theme/reduced-motion.generated.css"
  mkdir -p "$_wb_home/theme"

  if _wb_source="$(waybar_reduced_motion_active)"; then
    cat >"$_wb_out" <<EOF
/* Generated reduced-motion override — do not edit by hand */
/* active: true · source: ${_wb_source} */
/* GTK3 has no prefers-reduced-motion media query; this file is applied at launch. */

#custom-ws-0.ws-active,
#custom-ws-1.ws-active,
#custom-ws-2.ws-active,
#custom-ws-3.ws-active,
#custom-ws-4.ws-active,
#custom-ws-5.ws-active,
#custom-ws-6.ws-active,
#custom-ws-7.ws-active,
#custom-ws-8.ws-active,
#custom-ws-9.ws-active,
#workspaces button.active,
.critical,
#custom-cpu.critical,
#custom-gpu.critical,
#custom-memory.critical,
#custom-disk.critical,
#custom-nvme.critical,
#custom-psu.critical,
#custom-fans.critical,
#custom-liquidctl.critical,
#custom-coolercontrol.critical,
#custom-openlinkhub.critical,
#custom-stats-carousel.critical,
#custom-systemd.critical,
#idle_inhibitor.activated {
    animation: none;
}

#custom-cpu,
#custom-gpu,
#custom-memory,
#custom-disk,
#custom-nvme,
#custom-psu,
#custom-fans,
#custom-updates,
#custom-homelab,
#custom-ws-0.ws-hit,
#custom-ws-1.ws-hit,
#custom-ws-2.ws-hit,
#custom-ws-3.ws-hit,
#custom-ws-4.ws-hit,
#custom-ws-5.ws-hit,
#custom-ws-6.ws-hit,
#custom-ws-7.ws-hit,
#custom-ws-8.ws-hit,
#custom-ws-9.ws-hit,
#custom-dock-win-0.dock-win-hit,
#custom-dock-win-1.dock-win-hit,
#custom-dock-win-2.dock-win-hit,
#custom-dock-win-3.dock-win-hit,
#custom-dock-win-4.dock-win-hit,
#custom-dock-win-5.dock-win-hit,
#custom-dock-win-6.dock-win-hit,
#custom-dock-win-7.dock-win-hit,
#custom-dock-win-8.dock-win-hit,
#custom-dock-win-9.dock-win-hit,
#custom-dock-win-10.dock-win-hit,
#custom-dock-win-11.dock-win-hit,
#custom-dock-win-12.dock-win-hit,
#custom-dock-win-13.dock-win-hit,
#custom-dock-win-14.dock-win-hit,
#custom-dock-win-15.dock-win-hit {
    transition: none;
}
EOF
    return 0
  fi

  cat >"$_wb_out" <<'EOF'
/* Generated reduced-motion override — do not edit by hand */
/* active: false */
EOF
  return 0
}
