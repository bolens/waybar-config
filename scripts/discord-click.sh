#!/usr/bin/env sh
set -eu

mode="${1:-mute}"
log_file="${XDG_RUNTIME_DIR:-/tmp}/discord-click.log"

log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$log_file" 2>/dev/null || true
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
      log "Recovered HYPRLAND_INSTANCE_SIGNATURE=$sig"
      return 0
    fi
  fi

  log "Could not recover HYPRLAND_INSTANCE_SIGNATURE"
  return 1
}

notify() {
  title="$1"
  body="$2"
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify 0 2200 "rgb(89b4fa)" "fontsize:18  ${title} - ${body}" >/dev/null 2>&1 || true
  fi
  notify-send "$title" "$body" 2>/dev/null || true
}

hypr_dispatch() {
  args="$1"
  hyprctl dispatch "$args" 2>&1
}

send_discord_hotkey() {
  key="$1"
  hypr_error=""

  ensure_hypr_env || true

  if ! command -v hyprctl >/dev/null 2>&1; then
    notify "Discord" "hyprctl not available"
    log "hyprctl not available"
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
  log "Detected address=${address:-none} key=$key"

  if [ -n "$address" ] && [ "$address" != "null" ]; then
    if out=$(hypr_dispatch "sendshortcut ALT,$key,address:$address") && printf '%s' "$out" | rg -qi '^ok$'; then
      log "sendshortcut address OK"
      return 0
    fi
    hypr_error="$out"

    if out=$(hypr_dispatch "focuswindow address:$address") && printf '%s' "$out" | rg -qi '^ok$'; then
      log "focuswindow address OK"
      if out=$(hypr_dispatch "sendshortcut ALT,$key,activewindow") && printf '%s' "$out" | rg -qi '^ok$'; then
        log "sendshortcut activewindow OK"
        return 0
      fi
      hypr_error="$out"

      if out=$(hypr_dispatch "sendshortcut ALT,$key") && printf '%s' "$out" | rg -qi '^ok$'; then
        log "sendshortcut global OK"
        return 0
      fi
      hypr_error="$out"
    fi
  fi

  # Last fallback: send to currently active window.
  if out=$(hypr_dispatch "sendshortcut ALT,$key,activewindow") && printf '%s' "$out" | rg -qi '^ok$'; then
    log "fallback activewindow OK"
    return 0
  fi
  hypr_error="$out"

  if out=$(hypr_dispatch "sendshortcut ALT,$key") && printf '%s' "$out" | rg -qi '^ok$'; then
    log "fallback global OK"
    return 0
  fi
  hypr_error="$out"

  # Fallback path: focus Discord and synthesize the hotkey via wtype.
  if [ -n "$address" ] && [ "$address" != "null" ] && command -v wtype >/dev/null 2>&1; then
    if out=$(hypr_dispatch "focuswindow address:$address") && printf '%s' "$out" | rg -qi '^ok$'; then
      case "$key" in
        end)
          if wtype -M alt -k End -m alt >/dev/null 2>&1; then
            log "wtype End OK"
            return 0
          fi
          ;;
        home)
          if wtype -M alt -k Home -m alt >/dev/null 2>&1; then
            log "wtype Home OK"
            return 0
          fi
          ;;
      esac
    fi
  fi

  if [ -n "$hypr_error" ]; then
    log "hypr_error=$hypr_error"
    notify "Discord" "Hypr error: $(printf '%s' "$hypr_error" | tr '\n' ' ' | cut -c1-120)"
  fi

  return 1
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