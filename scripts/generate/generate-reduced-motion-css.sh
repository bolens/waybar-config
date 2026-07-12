#!/usr/bin/env bash
# Emit theme/reduced-motion.generated.css.
# Generate is deterministic: only "force" bakes an active override; "auto" stays inactive
# so CI drift does not depend on the host a11y preference. Launch applies live probes.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=../lib/reduced-motion-lib.sh
. "$WAYBAR_SCRIPTS/lib/reduced-motion-lib.sh"

# During `make generate` / CI, ignore host probes unless explicitly forced via settings/env.
if [ "${WAYBAR_REDUCED_MOTION_GENERATE_LIVE:-0}" != "1" ]; then
  mode="$(waybar_reduced_motion_mode | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    force | always | on | true | 1) ;;
    *)
      export WAYBAR_REDUCED_MOTION=0
      ;;
  esac
fi

waybar_apply_reduced_motion_css
