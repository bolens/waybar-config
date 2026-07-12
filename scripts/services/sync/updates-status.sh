#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fi
cache_file="$cache_dir/updates-status.json"
lock_dir="$cache_dir/updates-status.lock.d"
ttl="$(waybar_module_interval updates 300)"
stale_lock_ttl=120

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰚰 ..." "Checking for updates in background" "disabled"
  exit 0
fi

# shellcheck source=unicode-animations-lib.sh
. "$WAYBAR_SCRIPTS/lib/unicode-animations-lib.sh"

preview_limit=$(waybar_settings_get '.updates.preview_limit' '40')
updates_warn=$(waybar_settings_get '.thresholds.updates.warning' '1')
updates_crit=$(waybar_settings_get '.thresholds.updates.critical' '75')
enable_aur=$(waybar_settings_get '.updates.enable_aur' 'false')
if [ "${WAYBAR_UPDATES_ENABLE_AUR:-}" = "1" ]; then
  enable_aur=true
elif [ "${WAYBAR_UPDATES_ENABLE_AUR:-}" = "0" ]; then
  enable_aur=false
fi

# Detect package backend: Arch (checkupdates) → Debian/Ubuntu (apt) → Fedora (dnf).
# Flatpak is additive on every backend. Override with WAYBAR_UPDATES_BACKEND=arch|apt|dnf|none.
# Note: `apt` exists on some Arch boxes as a wrapper — checkupdates is preferred first.
detect_updates_backend() {
  if [ -n "${WAYBAR_UPDATES_BACKEND:-}" ]; then
    printf '%s' "$WAYBAR_UPDATES_BACKEND"
    return 0
  fi
  if command -v checkupdates >/dev/null 2>&1; then
    printf 'arch'
  elif command -v apt >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  else
    printf 'none'
  fi
}

# Read package list on stdin; set globals _out_count / _out_preview (bash has no namerefs here).
_count_preview() {
  local list preview_lim="$1"
  list=$(cat)
  _out_count=0
  _out_preview=""
  if [ -n "$list" ]; then
    _out_count=$(printf '%s\n' "$list" | awk 'NF {count++} END {print count + 0}')
    _out_preview=$(printf '%s\n' "$list" | sed -n "1,${preview_lim}p")
    if [ "$_out_count" -gt "$preview_lim" ]; then
      _out_preview=$(printf '%s\n... and %s more' "$_out_preview" "$((_out_count - preview_lim))")
    fi
  fi
}

perform_checks_and_output() {
  repo_count=0
  aur_count=0
  flatpak_count=0
  repo_preview=""
  aur_preview=""
  flatpak_preview=""
  backend=$(detect_updates_backend)
  repo_label="Repo"

  case "$backend" in
    arch)
      repo_label="Repo"
      if command -v checkupdates >/dev/null 2>&1; then
        repo_list=$(timeout 25 checkupdates 2>/dev/null || true)
        _count_preview "$preview_limit" <<<"$repo_list"
        repo_count=$_out_count
        repo_preview=$_out_preview
      fi
      if [ "$enable_aur" = "true" ] && command -v paru >/dev/null 2>&1; then
        aur_list=$(timeout 12 paru -Qua 2>/dev/null || true)
        _count_preview "$preview_limit" <<<"$aur_list"
        aur_count=$_out_count
        aur_preview=$_out_preview
      fi
      ;;
    apt)
      repo_label="APT"
      # Skip the "Listing... Done" header; keep lines with "/suite ... upgradable".
      repo_list=$(timeout 25 apt list --upgradable 2>/dev/null | grep -E '/[a-z].*upgradable' || true)
      _count_preview "$preview_limit" <<<"$repo_list"
      repo_count=$_out_count
      repo_preview=$_out_preview
      ;;
    dnf)
      repo_label="DNF"
      # dnf check-upgrade exits 100 when updates exist — ignore status, parse stdout.
      repo_list=$(timeout 40 dnf check-upgrade -q 2>/dev/null | awk 'NF && $1 !~ /^Obsoleting/ && $1 !~ /^Last/' || true)
      _count_preview "$preview_limit" <<<"$repo_list"
      repo_count=$_out_count
      repo_preview=$_out_preview
      ;;
    *)
      repo_label="Repo"
      ;;
  esac

  # Flatpak updates (additive on all distros):
  if command -v flatpak >/dev/null 2>&1; then
    flatpak_list=$(timeout 20 flatpak remote-ls --updates 2>/dev/null || true)
    _count_preview "$preview_limit" <<<"$flatpak_list"
    flatpak_count=$_out_count
    flatpak_preview=$_out_preview
  fi

  total=$((repo_count + aur_count + flatpak_count))
  total_text=$(printf '%3d' "$total")

  class="normal"
  if [ "$total" -ge "$updates_crit" ]; then
    class="critical"
  elif [ "$total" -ge "$updates_warn" ]; then
    class="warning"
  fi

  if [ "$backend" = "arch" ]; then
    tooltip=$(printf '%s updates: %s\nAUR updates: %s\nFlatpak updates: %s\nTotal updates: %s\nBackend: %s' \
      "$repo_label" "$repo_count" "$aur_count" "$flatpak_count" "$total" "$backend")
  else
    tooltip=$(printf '%s updates: %s\nFlatpak updates: %s\nTotal updates: %s\nBackend: %s' \
      "$repo_label" "$repo_count" "$flatpak_count" "$total" "$backend")
  fi

  if [ -n "$repo_preview" ]; then
    tooltip=$(printf '%s\n\n%s preview:\n%s' "$tooltip" "$repo_label" "$repo_preview")
  fi

  if [ -n "$aur_preview" ]; then
    tooltip=$(printf '%s\n\nAUR preview:\n%s' "$tooltip" "$aur_preview")
  fi

  if [ -n "$flatpak_preview" ]; then
    tooltip=$(printf '%s\n\nFlatpak preview:\n%s' "$tooltip" "$flatpak_preview")
  fi

  tooltip=$(printf '%s\n\nLeft: update · Right: review · Middle: refresh' "$tooltip")

  json=$(emit_waybar_json "󰚰 ${total_text}" "$tooltip" "$class")

  # Save cache
  tmp="$cache_file.tmp.$$"
  printf '%s\n' "$json" >"$tmp"
  mv -f "$tmp" "$cache_file"

  # Signal waybar if running in background
  if [ "${WAYBAR_BACKGROUND:-0}" = "1" ]; then
    sig_num=$(_get_config_override '.signals.updates' '1')
    if [ -n "$sig_num" ] && [ "$sig_num" != "null" ]; then
      "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig_num"
    fi
  fi

  # Print final JSON to stdout so animate_command displays it at the end
  printf '%s\n' "$json"
}

if [ "${1:-}" = "--refresh" ]; then
  animate_command clock "Checking updates..." "Connecting to mirrors..." perform_checks_and_output
else
  # If called without refresh, perform a one-shot check directly
  perform_checks_and_output >/dev/null
fi
