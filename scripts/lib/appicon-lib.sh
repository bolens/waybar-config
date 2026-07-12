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

# Negative-cache stamps so cold status ticks do not respawn appicon every signal.
waybar_appicon_miss_dir() {
  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/waybar/appicon-miss"
}

waybar_appicon_miss_clear() {
  local key="$1"
  [ -n "$key" ] || return 0
  rm -f "$(waybar_appicon_miss_dir)/${key}" 2>/dev/null || true
}

waybar_appicon_miss_mark() {
  local key="$1" dir
  [ -n "$key" ] || return 0
  dir="$(waybar_appicon_miss_dir)"
  mkdir -p "$dir"
  : >"${dir}/${key}"
}

# Return 0 when a recent miss stamp exists (skip resolve). TTL default 300s.
waybar_appicon_miss_fresh() {
  local key="$1" ttl="${2:-300}" stamp now mtime age
  [ -n "$key" ] || return 1
  stamp="$(waybar_appicon_miss_dir)/${key}"
  [ -f "$stamp" ] || return 1
  now="$(date +%s)"
  mtime="$(stat -c %Y "$stamp" 2>/dev/null || printf '0')"
  age=$((now - mtime))
  [ "$age" -ge 0 ] && [ "$age" -lt "$ttl" ]
}

# Resolve a PNG path via appicon. mode=offline (default, hot path) or online (prefetch).
# Prints absolute path on success. Uses appicon's XDG cache; offline never hits the network.
waybar_appicon_resolve() {
  local query="$1" size="$2" theme="$3" mode="${4:-offline}"
  local bin path
  [ -n "$query" ] || return 1
  [ -n "$size" ] || size=18
  [ -n "$theme" ] || theme=dark
  bin="$(waybar_appicon_bin)" || return 1
  if [ "$mode" = "online" ]; then
    path="$("$bin" resolve --format png --size "$size" --theme "$theme" "$query" 2>/dev/null || true)"
  else
    path="$("$bin" resolve --offline --format png --size "$size" --theme "$theme" "$query" 2>/dev/null || true)"
  fi
  if [ -n "$path" ] && [ -f "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi
  return 1
}

# GTK3/Waybar often ignores background-size — materialize exact NxN PNGs.
# Warm path: existing non-empty dest PNG is reused (no re-rasterize).
waybar_appicon_materialize() {
  local src="$1"
  local dest="$2"
  local size="$3"
  local tmp png

  [ -n "$size" ] || size=18
  png="${dest}.png"

  if [ -f "$png" ] && [ -s "$png" ] && [ "${WAYBAR_APPICON_REMATERIALIZE:-0}" != "1" ]; then
    ln -sfn "$(basename "$png")" "$dest" 2>/dev/null || ln -sfn "$png" "$dest" 2>/dev/null || true
    return 0
  fi

  [ -f "$src" ] || return 1
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
    # Last resort: copy/symlink into dest.png so warm paths that look for *.png still hit.
    mkdir -p "$(dirname "$png")"
    if ! cp -f "$src" "$png" 2>/dev/null; then
      ln -sfn "$src" "$png" 2>/dev/null || return 1
    fi
    ln -sfn "$(basename "$png")" "$dest" 2>/dev/null || ln -sfn "$png" "$dest" 2>/dev/null || true
    [ -e "$dest" ] || [ -f "$png" ] || [ -e "$png" ]
    return
  fi

  mv -f "$tmp" "$png"
  ln -sfn "$(basename "$png")" "$dest" 2>/dev/null || ln -sfn "$png" "$dest" 2>/dev/null || true
  [ -e "$dest" ] || [ -f "$png" ]
}
