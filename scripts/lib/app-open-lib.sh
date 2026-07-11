#!/usr/bin/env bash
# Launch helpers for whitespace-separated command strings from settings.
#
# Settings keys (apps.*, update commands, etc.) store a single string that may
# contain multiple argv words. Unquoted expansion triggers SC2086 and globs;
# this helper splits safely and delegates to tools/app-open.sh.

: "${WAYBAR_SCRIPTS:=${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts}"

# Split $1 on IFS whitespace into argv and run via app-open.sh.
# Returns 64 if the command string is empty.
waybar_app_open() {
  local cmd="${1:-}"
  local -a args=()

  # Trim leading/trailing whitespace.
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"
  [ -n "$cmd" ] || return 64

  # Disable globbing while splitting so settings like `foo *` stay literal.
  set -f
  # Default IFS whitespace split into argv (no pathname expansion).
  # read -a avoids SC2086 at call sites and SC2206 array=(...).
  read -r -a args <<<"$cmd"
  set +f

  [ "${#args[@]}" -gt 0 ] || return 64
  "$WAYBAR_SCRIPTS/tools/app-open.sh" "${args[@]}"
}

# Same as waybar_app_open but replaces the current process.
waybar_app_open_exec() {
  local cmd="${1:-}"
  local -a args=()

  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"
  [ -n "$cmd" ] || exit 64

  set -f
  read -r -a args <<<"$cmd"
  set +f

  [ "${#args[@]}" -gt 0 ] || exit 64
  exec "$WAYBAR_SCRIPTS/tools/app-open.sh" "${args[@]}"
}
