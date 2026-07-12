#!/usr/bin/env bash
# Emit theme/animations.generated.css from visual.animations flags.
# GTK3 CSS only supports simple from/to (or single %) keyframes — not "0%, 100%".
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$theme_dir"
out="$theme_dir/animations.generated.css"

workspace_pulse=$(jq -r '.visual.animations.workspace_pulse // false' "$settings")
critical_breathe=$(jq -r '.visual.animations.critical_breathe // false' "$settings")
idle_glow=$(jq -r '.visual.animations.idle_glow // false' "$settings")

{
  printf '%s\n\n' '/* Generated from visual.animations — do not edit by hand */'

  if [ "$workspace_pulse" = "true" ]; then
    cat <<'EOF'
/* Active workspace soft pulse (GTK3: from/to + alternate only) */
@keyframes waybar-workspace-pulse {
    from {
        box-shadow: 0 0 0 0 rgba(255, 42, 127, 0.0);
    }
    to {
        box-shadow: 0 0 10px 2px rgba(255, 42, 127, 0.35);
    }
}

#custom-ws-0.ws-active,
#custom-ws-1.ws-active,
#custom-ws-2.ws-active,
#custom-ws-3.ws-active,
#custom-ws-4.ws-active,
#custom-ws-5.ws-active,
#custom-ws-6.ws-active,
#custom-ws-7.ws-active,
#custom-ws-8.ws-active,
#custom-ws-9.ws-active,
#workspaces button.active {
    animation: waybar-workspace-pulse 2.4s ease-in-out infinite alternate;
}

EOF
  fi

  if [ "$critical_breathe" = "true" ]; then
    cat <<'EOF'
/* Critical modules breathe (generalizes security-blink) */
@keyframes waybar-critical-breathe {
    to {
        background-color: rgba(255, 42, 127, 0.25);
        box-shadow: 0 0 12px rgba(255, 42, 127, 0.4);
    }
}

.critical,
#custom-cpu.critical,
#custom-gpu.critical,
#custom-memory.critical,
#custom-disk.critical,
#custom-nvme.critical,
#custom-psu.critical,
#custom-fans.critical,
#custom-liquidctl.critical,
#custom-coolercontrol.critical,
#custom-openlinkhub.critical,
#custom-stats-carousel.critical,
#custom-systemd.critical {
    animation: waybar-critical-breathe 1s steps(12, start) infinite alternate;
}

EOF
  fi

  if [ "$idle_glow" = "true" ]; then
    cat <<'EOF'
/* Idle inhibitor soft cyan glow when active */
@keyframes waybar-idle-glow {
    from {
        box-shadow: 0 0 4px rgba(0, 229, 255, 0.2);
    }
    to {
        box-shadow: 0 0 12px rgba(0, 229, 255, 0.45);
    }
}

#idle_inhibitor.activated {
    animation: waybar-idle-glow 2.8s ease-in-out infinite alternate;
}

EOF
  fi
} >"$out"
