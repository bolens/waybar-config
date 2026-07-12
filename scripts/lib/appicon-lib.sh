#!/usr/bin/env bash
# Shared helpers for bolens/appicon (dock PNG proof). Never embeds SVGL URLs.
# shellcheck shell=bash

waybar_appicon_bin() {
  if [ -n "${APPICON_BIN:-}" ] && [ -x "$APPICON_BIN" ]; then
    printf '%s\n' "$APPICON_BIN"
    return 0
  fi
  if command -v appicon >/dev/null 2>&1; then
    command -v appicon
    return 0
  fi
  local candidate
  for candidate in \
    "${HOME}/.local/bin/appicon" \
    "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/bin/appicon"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

waybar_appicon_enabled() {
  local enabled
  if ! type waybar_settings_get >/dev/null 2>&1; then
    return 1
  fi
  enabled="$(waybar_settings_get '.icons.appicon.enabled' 'false')"
  case "$enabled" in
    true | True | TRUE | 1 | yes | Yes | YES | on | On | ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve size for crisp PNGs (CSS may display smaller via icons.appicon.size).
waybar_appicon_resolve_size() {
  local display="${1:-22}"
  if [ "$display" -lt 48 ] 2>/dev/null; then
    printf '48\n'
  else
    printf '%s\n' "$display"
  fi
}
