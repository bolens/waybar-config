#!/usr/bin/env bash
# Emit theme/submap-per-output.generated.css from hypr_tools.submap_per_output.
# Submaps are session-global; when enabled we only scope presentation CSS under
# window.<OUTPUT> (Waybar's per-monitor bar class) — never fake per-monitor submap state.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=../lib/output-lib.sh
. "$WAYBAR_SCRIPTS/lib/output-lib.sh"

settings="$WAYBAR_HOME/data/waybar-settings.json"
theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$theme_dir"
out="$theme_dir/submap-per-output.generated.css"

enabled=$(jq -r '.hypr_tools.submap_per_output // false' "$settings" 2>/dev/null || printf 'false')

case "$enabled" in
  true | True | TRUE | 1 | yes | Yes | YES | on | On | ON) ;;
  *)
    cat >"$out" <<'EOF'
/* Generated — hypr_tools.submap_per_output is off; no per-output submap CSS. */
EOF
    exit 0
    ;;
esac

mapfile -t outputs < <(waybar_list_outputs || true)
if [ "${#outputs[@]}" -eq 0 ]; then
  # Hermetic fallback so generate always produces scoped selectors when enabled.
  outputs=(eDP-1 DP-1 HDMI-A-1)
fi

{
  printf '%s\n' '/* Generated from hypr_tools.submap_per_output — do not edit by hand */'
  printf '%s\n' '/* Submap state is session-global; cues are scoped per bar window.<OUTPUT>. */'
  printf '\n'

  first=1
  for name in "${outputs[@]}"; do
    [ -n "$name" ] || continue
    cls="$(waybar_css_class_for_output "$name")"
    [ -n "$cls" ] || continue
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ',\n'
    fi
    printf 'window.%s #submap' "$cls"
  done
  if [ "$first" -eq 1 ]; then
    # No valid outputs after sanitize — keep file valid.
    printf '%s\n' '/* no outputs to scope */'
  else
    printf ' {\n'
    cat <<'EOF'
    /* Per-output chrome for the shared session submap on each bar. */
    font-weight: 700;
    letter-spacing: 0.02em;
}
EOF
  fi
} >"$out"
