#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
cache_file="$cache_dir/updates-status.json"
lock_dir="$cache_dir/updates-status.lock.d"
ttl=300
stale_lock_ttl=120

mkdir -p "$cache_dir"


if [ "${1:-}" != "--refresh" ]; then
  age=$(cache_file_age "$cache_file")
  if [ "$age" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    exit 0
  fi

  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"

  if [ -f "$cache_file" ]; then
    [ -d "$lock_dir" ] || refresh_in_background
    cat "$cache_file"
    exit 0
  fi

  [ -d "$lock_dir" ] || refresh_in_background
  jq -cn \
    --arg text "󰚰 ..." \
    --arg tooltip "Checking for updates in background" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

# shellcheck source=unicode-animations-lib.sh
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/unicode-animations-lib.sh"

preview_limit=40

perform_checks_and_output() {
  repo_count=0
  aur_count=0
  flatpak_count=0
  repo_preview=""
  aur_preview=""
  flatpak_preview=""

  # Official repository updates check (Pacman):
  if command -v checkupdates >/dev/null 2>&1; then
    repo_list=$(timeout 25 checkupdates 2>/dev/null || true)
    if [ -n "$repo_list" ]; then
      repo_count=$(printf '%s\n' "$repo_list" | awk 'NF {count++} END {print count + 0}')
      repo_preview=$(printf '%s\n' "$repo_list" | sed -n "1,${preview_limit}p")
      if [ "$repo_count" -gt "$preview_limit" ]; then
        repo_preview=$(printf '%s\n... and %s more' "$repo_preview" "$((repo_count - preview_limit))")
      fi
    fi
  fi

  # AUR updates check:
  if [ "${WAYBAR_UPDATES_ENABLE_AUR:-0}" = "1" ] && command -v paru >/dev/null 2>&1; then
    aur_list=$(timeout 12 paru -Qua 2>/dev/null || true)
    if [ -n "$aur_list" ]; then
      aur_count=$(printf '%s\n' "$aur_list" | awk 'NF {count++} END {print count + 0}')
      aur_preview=$(printf '%s\n' "$aur_list" | sed -n "1,${preview_limit}p")
      if [ "$aur_count" -gt "$preview_limit" ]; then
        aur_preview=$(printf '%s\n... and %s more' "$aur_preview" "$((aur_count - preview_limit))")
      fi
    fi
  fi

  # Flatpak updates check:
  if command -v flatpak >/dev/null 2>&1; then
    flatpak_list=$(timeout 20 flatpak remote-ls --updates 2>/dev/null || true)
    if [ -n "$flatpak_list" ]; then
      flatpak_count=$(printf '%s\n' "$flatpak_list" | awk 'NF {count++} END {print count + 0}')
      flatpak_preview=$(printf '%s\n' "$flatpak_list" | sed -n "1,${preview_limit}p")
      if [ "$flatpak_count" -gt "$preview_limit" ]; then
        flatpak_preview=$(printf '%s\n... and %s more' "$flatpak_preview" "$((flatpak_count - preview_limit))")
      fi
    fi
  fi

  total=$((repo_count + aur_count + flatpak_count))
  total_text=$(printf '%3d' "$total")

  class="normal"
  if [ "$total" -ge 75 ]; then
    class="critical"
  elif [ "$total" -gt 0 ]; then
    class="warning"
  fi

  tooltip=$(printf 'Repo updates: %s\nAUR updates: %s\nFlatpak updates: %s\nTotal updates: %s' "$repo_count" "$aur_count" "$flatpak_count" "$total")

  if [ -n "$repo_preview" ]; then
    tooltip=$(printf '%s\n\nRepo preview:\n%s' "$tooltip" "$repo_preview")
  fi

  if [ -n "$aur_preview" ]; then
    tooltip=$(printf '%s\n\nAUR preview:\n%s' "$tooltip" "$aur_preview")
  fi

  if [ -n "$flatpak_preview" ]; then
    tooltip=$(printf '%s\n\nFlatpak preview:\n%s' "$tooltip" "$flatpak_preview")
  fi

  json=$(jq -cn \
    --arg text "󰚰 ${total_text}" \
    --arg tooltip "$tooltip" \
    --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}')

  # Save cache
  tmp="$cache_file.tmp.$$"
  printf '%s\n' "$json" > "$tmp"
  mv -f "$tmp" "$cache_file"

  # Print final JSON to stdout so animate_command displays it at the end
  printf '%s\n' "$json"
}

if [ "${1:-}" = "--refresh" ]; then
  animate_command clock "Checking updates..." "Connecting to mirrors..." perform_checks_and_output
else
  # If called without refresh, perform a one-shot check directly
  perform_checks_and_output >/dev/null
fi