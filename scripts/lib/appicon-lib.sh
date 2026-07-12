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

# GTK3/Waybar often ignores background-size — materialize exact NxN PNGs.
waybar_appicon_materialize() {
  local src="$1"
  local dest="$2"
  local size="$3"
  local tmp png

  [ -f "$src" ] || return 1
  [ -n "$size" ] || size=18
  png="${dest}.png"
  tmp="${png}.tmp.$$"

  if command -v magick >/dev/null 2>&1; then
    if ! magick "$src" -resize "${size}x${size}" -background none -gravity center \
      -extent "${size}x${size}" "png32:$tmp" 2>/dev/null; then
      rm -f "$tmp"
      return 1
    fi
  elif command -v convert >/dev/null 2>&1; then
    if ! convert "$src" -resize "${size}x${size}" -background none -gravity center \
      -extent "${size}x${size}" "png32:$tmp" 2>/dev/null; then
      rm -f "$tmp"
      return 1
    fi
  elif command -v rsvg-convert >/dev/null 2>&1 && [[ "$src" == *.svg || "$src" == *.SVG ]]; then
    if ! rsvg-convert -w "$size" -h "$size" -o "$tmp" "$src" 2>/dev/null; then
      rm -f "$tmp"
      return 1
    fi
  else
    # Last resort: symlink original (may be oversized in GTK).
    ln -sfn "$src" "$dest" 2>/dev/null || return 1
    return 0
  fi

  mv -f "$tmp" "$png"
  ln -sfn "$(basename "$png")" "$dest" 2>/dev/null || ln -sfn "$png" "$dest" 2>/dev/null || true
  [ -e "$dest" ] || [ -f "$png" ]
}
