#!/usr/bin/env bash
# Cache MPRIS album art and emit Waybar custom-module JSON (hide-empty-text).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
mkdir -p "$cache_dir"
art_base="$cache_dir/album-art"
enabled=$(waybar_settings_get '.visual.album_art.enabled' 'false')

emit_hidden() {
  emit_waybar_json "" "${1:-No album art}" "hidden"
}

case "$enabled" in
  true | True | TRUE | 1 | yes | Yes | YES | on | On | ON) ;;
  *)
    emit_hidden "Album art disabled"
    exit 0
    ;;
esac

if ! command -v playerctl >/dev/null 2>&1; then
  emit_hidden "playerctl not installed"
  exit 0
fi

if ! playerctl status >/dev/null 2>&1; then
  rm -f "$art_base" "$art_base".* 2>/dev/null || true
  emit_hidden "No active player"
  exit 0
fi

art_url=$(playerctl metadata mpris:artUrl 2>/dev/null || true)
title=$(playerctl metadata --format '{{title}}' 2>/dev/null || true)
artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null || true)
tooltip=$(printf '%s\n%s' "${title:-Unknown}" "${artist:-}")

if [ -z "$art_url" ]; then
  rm -f "$art_base" "$art_base".* 2>/dev/null || true
  emit_hidden "No album art"
  exit 0
fi

src=""
case "$art_url" in
  file://*)
    src="${art_url#file://}"
    # Decode %XX escapes when python is available.
    if command -v python3 >/dev/null 2>&1; then
      src=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$src" 2>/dev/null || printf '%s' "$src")
    fi
    ;;
  http://* | https://*)
    src="$art_url"
    ;;
  /*)
    src="$art_url"
    ;;
  *)
    emit_hidden "Unsupported art URL"
    exit 0
    ;;
esac

ext="img"
case "$src" in
  *.png | *.PNG) ext="png" ;;
  *.jpg | *.jpeg | *.JPG | *.JPEG) ext="jpg" ;;
  *.webp | *.WEBP) ext="webp" ;;
esac
dest="${art_base}.${ext}"

fetch_ok=0
case "$src" in
  http://* | https://*)
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL --max-time 5 -o "$dest.tmp" "$src" 2>/dev/null; then
        mv -f "$dest.tmp" "$dest"
        fetch_ok=1
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -O "$dest.tmp" "$src" 2>/dev/null; then
        mv -f "$dest.tmp" "$dest"
        fetch_ok=1
      fi
    fi
    ;;
  *)
    if [ -f "$src" ] && [ -r "$src" ]; then
      cp -f "$src" "$dest" 2>/dev/null && fetch_ok=1
    fi
    ;;
esac

if [ "$fetch_ok" -ne 1 ] || [ ! -s "$dest" ]; then
  rm -f "$dest.tmp" 2>/dev/null || true
  emit_hidden "Album art unavailable"
  exit 0
fi

ln -sfn "$dest" "$art_base" 2>/dev/null || cp -f "$dest" "$art_base" 2>/dev/null || true

# Non-empty text so the module shows; hide-empty-text collapses when no art.
emit_waybar_json "󰎆" "$tooltip" "album-art"
