#!/usr/bin/env sh
# Discord mute/deafen hotkeys — Hyprland via hyprctl, Plasma via focus + wtype/ydotool.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

mode="${1:-mute}"
log_file="${XDG_RUNTIME_DIR:-/tmp}/discord-click.log"

log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >>"$log_file" 2>/dev/null || true
}

notify() {
  title="$1"
  body="$2"
  if [ "$(detect_compositor)" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify 0 2200 "rgb(89b4fa)" "fontsize:18  ${title} - ${body}" >/dev/null 2>&1 || true
  fi
  notify-send "$title" "$body" 2>/dev/null || true
}

ensure_hypr_env() {
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    return 0
  fi
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  hypr_root="$runtime_dir/hypr"
  if [ -d "$hypr_root" ]; then
    sig=$(ls -1t "$hypr_root" 2>/dev/null | head -n1 || true)
    if [ -n "$sig" ]; then
      export HYPRLAND_INSTANCE_SIGNATURE="$sig"
      return 0
    fi
  fi
  return 1
}

hypr_dispatch() {
  hyprctl dispatch "$1" 2>&1
}

send_key_synth() {
  key="$1"
  case "$key" in
    end)
      if command -v wtype >/dev/null 2>&1; then
        wtype -M alt -k End -m alt >/dev/null 2>&1 && return 0
      fi
      if command -v ydotool >/dev/null 2>&1; then
        # Alt+End: KEY_LEFTALT=56, KEY_END=107
        ydotool key 56:1 107:1 107:0 56:0 >/dev/null 2>&1 && return 0
      fi
      if command -v xdotool >/dev/null 2>&1; then
        xdotool key alt+End >/dev/null 2>&1 && return 0
      fi
      ;;
    home)
      if command -v wtype >/dev/null 2>&1; then
        wtype -M alt -k Home -m alt >/dev/null 2>&1 && return 0
      fi
      if command -v ydotool >/dev/null 2>&1; then
        ydotool key 56:1 102:1 102:0 56:0 >/dev/null 2>&1 && return 0
      fi
      if command -v xdotool >/dev/null 2>&1; then
        xdotool key alt+Home >/dev/null 2>&1 && return 0
      fi
      ;;
  esac
  return 1
}

focus_discord_kde() {
  if command -v kdotool >/dev/null 2>&1; then
    kdotool search --class discord windowactivate >/dev/null 2>&1 && return 0
    kdotool search --name Discord windowactivate >/dev/null 2>&1 && return 0
  fi
  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -xa discord >/dev/null 2>&1 && return 0
    wmctrl -a Discord >/dev/null 2>&1 && return 0
  fi
  # Best-effort: launch focus via desktop file activation if already running.
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.kappmenu /KAppMenu org.kde.kappmenu >/dev/null 2>&1 || true
  fi
  return 1
}

send_discord_hotkey_hypr() {
  key="$1"
  hypr_error=""
  ensure_hypr_env || true

  if ! command -v hyprctl >/dev/null 2>&1; then
    notify "Discord" "hyprctl not available"
    return 1
  fi

  clients_json=$(hyprctl -j clients 2>/dev/null || true)
  address=""
  if [ -n "$clients_json" ]; then
    address=$(printf '%s' "$clients_json" | jq -r '
      .[]
      | select(
          ((.class // "") | ascii_downcase | contains("discord"))
          or
          ((.initialClass // "") | ascii_downcase | contains("discord"))
          or
          ((.title // "") | ascii_downcase | contains("discord"))
        )
      | .address
    ' | head -n1)
  fi

  if [ -n "$address" ] && [ "$address" != "null" ]; then
    if out=$(hypr_dispatch "sendshortcut ALT,$key,address:$address") && printf '%s' "$out" | rg -qi '^ok$'; then
      return 0
    fi
    hypr_error="$out"
    if out=$(hypr_dispatch "focuswindow address:$address") && printf '%s' "$out" | rg -qi '^ok$'; then
      if out=$(hypr_dispatch "sendshortcut ALT,$key,activewindow") && printf '%s' "$out" | rg -qi '^ok$'; then
        return 0
      fi
      hypr_error="$out"
    fi
  fi

  if out=$(hypr_dispatch "sendshortcut ALT,$key,activewindow") && printf '%s' "$out" | rg -qi '^ok$'; then
    return 0
  fi
  hypr_error="$out"

  if [ -n "$address" ] && [ "$address" != "null" ]; then
    hypr_dispatch "focuswindow address:$address" >/dev/null 2>&1 || true
    sleep 0.15
    if send_key_synth "$key"; then
      return 0
    fi
  fi

  if [ -n "$hypr_error" ]; then
    log "hypr_error=$hypr_error"
  fi
  return 1
}

send_discord_hotkey_kde() {
  key="$1"
  focus_discord_kde || true
  sleep 0.2
  if send_key_synth "$key"; then
    return 0
  fi
  notify "Discord" "Need wtype, ydotool, or xdotool to send hotkeys on Plasma"
  return 1
}

send_discord_hotkey() {
  key="$1"
  case "$(detect_compositor)" in
    hyprland) send_discord_hotkey_hypr "$key" ;;
    kde) send_discord_hotkey_kde "$key" ;;
    *)
      if command -v hyprctl >/dev/null 2>&1; then
        send_discord_hotkey_hypr "$key"
      else
        send_discord_hotkey_kde "$key"
      fi
      ;;
  esac
}

case "$mode" in
  mute)
    if send_discord_hotkey end; then
      notify "Discord" "Sent Alt+End (toggle mute)"
    else
      notify "Discord" "Could not send mute hotkey to Discord (is it open?)"
    fi
    ;;
  deafen)
    if send_discord_hotkey home; then
      notify "Discord" "Sent Alt+Home (toggle deafen)"
    else
      notify "Discord" "Could not send deafen hotkey to Discord (is it open?)"
    fi
    ;;
  *)
    exit 1
    ;;
esac
