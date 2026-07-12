#!/usr/bin/env sh
# Shared cache, lock, interval, and JSON emit helpers for Waybar status scripts.

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
waybar_module_interval() {
  # Usage: waybar_module_interval <key> [fallback]
  # Reads module_intervals from compiled settings JSON.
  # "once" → long cache TTL (signal-driven modules should not be re-probed by libraries).
  key="$1"
  fallback="${2:-60}"
  settings="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/waybar-settings.json"
  if [ ! -f "$settings" ] || ! command -v jq >/dev/null 2>&1; then
    printf '%s' "$fallback"
    return
  fi
  val="$(jq -r --arg k "$key" --argjson fb "$fallback" '
    (.module_intervals[$k] // .poll_intervals[$k] // $fb) as $v
    | if ($v|type) == "number" then $v
      # "once" → day-long TTL for signal-driven modules (not re-probed by libs).
      elif $v == "once" then 86400
      else $fb end
  ' "$settings" 2>/dev/null || printf '%s' "$fallback")"
  printf '%s' "$val"
}

cache_file_age() {
  file="$1"
  # Missing file → huge age so callers always treat cache as stale.
  [ -f "$file" ] || {
    printf '%s' 999999
    return
  }
  if [ -n "${BASH_VERSION:-}" ] && [ -n "${EPOCHSECONDS:-}" ]; then
    now="$EPOCHSECONDS"
  else
    now=$(date +%s)
  fi
  mtime=$(stat -c %Y "$file" 2>/dev/null || printf '%s' 0)
  printf '%s' $((now - mtime))
}

read_fresh_cache_file() {
  file="$1"
  ttl="$2"
  age=$(cache_file_age "$file")
  [ "$age" -le "$ttl" ] 2>/dev/null || return 1
  cat "$file"
}

cleanup_stale_tmp_files() {
  dir="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar}"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name '*.tmp.*' -mtime +0 -delete 2>/dev/null || true
}

# Drop cache files the current user cannot overwrite (e.g. root-owned leftovers).
# Also drop owner-without-write modes (0444): root still passes test -w on those.
ensure_cache_writable() {
  file="$1"
  [ -e "$file" ] || return 0
  if [ -w "$file" ]; then
    case "$(stat -c %A "$file" 2>/dev/null || true)" in
      ?w*) return 0 ;;
    esac
  fi
  rm -f "$file" 2>/dev/null || true
}

cleanup_stale_lock_dir() {
  lock_dir="$1"
  stale_lock_ttl="${2:-30}"

  [ -d "$lock_dir" ] || return 0

  lock_pid_file="$lock_dir/pid"
  lock_pid=""
  if [ -f "$lock_pid_file" ]; then
    lock_pid=$(sed -n '1p' "$lock_pid_file" 2>/dev/null || true)
  fi

  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    return 0
  fi

  if [ -n "$lock_pid" ] || [ -f "$lock_pid_file" ]; then
    rm -f "$lock_pid_file"
    rmdir "$lock_dir" 2>/dev/null || true
    return 0
  fi

  now=$(date +%s)
  lock_mtime=$(stat -c %Y "$lock_dir" 2>/dev/null || printf '%s' 0)
  [ $((now - lock_mtime)) -gt "$stale_lock_ttl" ] 2>/dev/null || return 0

  rmdir "$lock_dir" 2>/dev/null || true
}

refresh_in_background() {
  local_lock_dir="${1:-$lock_dir}"
  local_script_path="${2:-$0}"

  mkdir "$local_lock_dir" 2>/dev/null || return 0
  (
    lock_pid_file="$local_lock_dir/pid"
    # Invoked via trap EXIT/INT/TERM.
    # shellcheck disable=SC2329
    cleanup_lock() {
      rm -f "$lock_pid_file"
      rmdir "$local_lock_dir" 2>/dev/null || true
    }
    trap cleanup_lock EXIT INT TERM
    WAYBAR_BACKGROUND=1 "$local_script_path" --refresh >/dev/null 2>&1 || true
  ) >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$local_lock_dir/pid"
}
serve_cache_or_refresh() {
  # Prefer serving stale JSON over a blank module while a background refresh
  # holds the lock; only return 1 when there is no cache file at all.
  local cache_file="$1"
  local ttl="$2"
  local lock_dir="$3"
  local stale_lock_ttl="$4"
  local script_path="${5:-$0}"

  if [ -f "$cache_file" ] && [ "$(cache_file_age "$cache_file")" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    return 0
  fi

  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"
  [ -d "$lock_dir" ] || refresh_in_background "$lock_dir" "$script_path"

  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi
  return 1
}

serve_metrics_cache_or_refresh() {
  local cached_file="$1"
  local ttl="$2"
  local cache_dir="$3"
  local script_dir="$4"

  if [ -f "$cached_file" ] && [ "$(cache_file_age "$cached_file")" -le "$ttl" ] 2>/dev/null; then
    cat "$cached_file"
    return 0
  fi

  if [ -f "$cached_file" ]; then
    cat "$cached_file"
    if [ ! -d "$cache_dir/system-metrics.lock.d" ]; then
      "$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" --refresh >/dev/null 2>&1 &
    fi
    return 0
  fi
  return 1
}

escape_markup() {
  # Escapes pango/HTML-ish specials. Pass the string as $1 — does not read stdin.
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

json_escape() {
  printf '%s' "$1" | awk 'BEGIN{RS=""; ORS=""} {
    gsub(/\\/, "\\\\")
    gsub(/"/, "\\\"")
    gsub(/\n/, "\\n")
    printf "%s", $0
  }'
}

emit_waybar_json() {
  local text="$1"
  local tooltip="$2"
  local class="${3:-normal}"

  # Expand backslash-n (\n) to real newlines
  local tooltip_expanded
  tooltip_expanded=$(printf '%b' "$tooltip")

  # Escape Pango/XML markup
  local esc_text
  esc_text=$(escape_markup "$text")
  local esc_tooltip
  esc_tooltip=$(escape_markup "$tooltip_expanded")

  # Output as JSON using jq
  jq -cn \
    --arg text "$esc_text" \
    --arg tooltip "$esc_tooltip" \
    --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

# Atomic cache write + stdout + exit 0.
# Usage: write_cache_and_exit JSON [CACHE_FILE]
# CACHE_FILE defaults to $cache_file (must be set in caller scope).
write_cache_and_exit() {
  _json="$1"
  _dest="${2:-${cache_file:?write_cache_and_exit: cache_file unset}}"
  printf '%s\n' "$_json"
  _tmp="$_dest.tmp.$$"
  if printf '%s\n' "$_json" >"$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$_dest" 2>/dev/null || rm -f "$_tmp" 2>/dev/null || true
  fi
  exit 0
}

# Emit empty-text disconnected status, cache, and exit.
# Usage: emit_disconnected TOOLTIP [CACHE_FILE]
emit_disconnected() {
  write_cache_and_exit "$(emit_waybar_json "" "$1" "disconnected")" "${2:-}"
}

# Map numeric value(s) to Waybar class.
# Usage: waybar_threshold_class VALUE WARN CRIT [VALUE WARN CRIT ...]
# Any triple at/above CRIT → critical; else any at/above WARN → warning; else normal.
# Non-numeric values are ignored for that triple.
waybar_threshold_class() {
  _class=normal
  while [ "$#" -ge 3 ]; do
    _v="$1"
    _w="$2"
    _c="$3"
    shift 3
    if [ "$_v" -ge "$_c" ] 2>/dev/null; then
      _class=critical
    elif [ "$_class" != critical ] && [ "$_v" -ge "$_w" ] 2>/dev/null; then
      _class=warning
    fi
  done
  printf '%s' "$_class"
}
