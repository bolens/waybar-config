#!/usr/bin/env bash
# Smoke-check systemd unit templates point at real scripts under WAYBAR_HOME.
set -euo pipefail

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
fail=0
unit_dir="$WAYBAR_HOME/systemd"

if [ ! -d "$unit_dir" ]; then
  printf 'FAIL missing systemd/ templates under %s\n' "$WAYBAR_HOME" >&2
  exit 1
fi

check_path() {
  local unit="$1"
  local raw="$2"
  local rel="${raw#%h/.config/waybar/}"
  if [ "$rel" = "$raw" ]; then
    # Not a %h/.config/waybar path (e.g. /usr/bin/bash) — skip
    return 0
  fi
  local target="$WAYBAR_HOME/$rel"
  if [ ! -e "$target" ]; then
    printf 'FAIL %s references missing path: %s (-> %s)\n' "$unit" "$raw" "$target" >&2
    fail=1
    return 1
  fi
  case "$target" in
    *.sh)
      if [ ! -x "$target" ]; then
        printf 'FAIL %s references non-executable script: %s\n' "$unit" "$target" >&2
        fail=1
      fi
      ;;
  esac
}

shopt -s nullglob
for unit in "$unit_dir"/*.service "$unit_dir"/*.timer; do
  [ -f "$unit" ] || continue
  base=$(basename "$unit")
  printf 'ok checking %s\n' "$base"

  # Paths that should exist under the repo when using %h/.config/waybar
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    check_path "$base" "$raw"
  done < <(grep -oE '%h/\.config/waybar/[^[:space:]"]+' "$unit" || true)

  # Environment=WAYBAR_HOME / WAYBAR_SCRIPTS must use portable %h form
  if grep -q '^Environment=WAYBAR_HOME=' "$unit" 2>/dev/null; then
    if ! grep -q '^Environment=WAYBAR_HOME=%h/\.config/waybar$' "$unit"; then
      printf 'FAIL %s: WAYBAR_HOME must be %%h/.config/waybar\n' "$base" >&2
      fail=1
    fi
  fi
  if grep -q '^Environment=WAYBAR_SCRIPTS=' "$unit" 2>/dev/null; then
    if ! grep -q '^Environment=WAYBAR_SCRIPTS=%h/\.config/waybar/scripts$' "$unit"; then
      printf 'FAIL %s: WAYBAR_SCRIPTS must be %%h/.config/waybar/scripts\n' "$base" >&2
      fail=1
    fi
  fi
done

# Timer must point at the healthcheck service unit name
if [ -f "$unit_dir/waybar-healthcheck.timer" ]; then
  if ! grep -q '^Unit=waybar-healthcheck\.service$' "$unit_dir/waybar-healthcheck.timer"; then
    printf 'FAIL waybar-healthcheck.timer must Unit=waybar-healthcheck.service\n' >&2
    fail=1
  fi
fi

# Unit templates must stay portable (no /home/panda absolute ExecStart — journal regression).
if grep -R -nE '/home/[^/]+/' "$unit_dir" --include='*.service' --include='*.timer' >/dev/null 2>&1; then
  printf 'FAIL systemd templates contain absolute /home/ paths:\n' >&2
  grep -R -nE '/home/[^/]+/' "$unit_dir" --include='*.service' --include='*.timer' >&2 || true
  fail=1
fi

if [ -f "$unit_dir/waybar.service" ] && ! grep -q '^SyslogIdentifier=waybar$' "$unit_dir/waybar.service"; then
  printf 'FAIL waybar.service missing SyslogIdentifier=waybar\n' >&2
  fail=1
fi

exit "$fail"
