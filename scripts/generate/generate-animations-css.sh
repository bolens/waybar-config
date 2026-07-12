#!/usr/bin/env bash
# Emit theme/animations.generated.css from visual.animations flags.
# GTK3 CSS only supports simple from/to (or single %) keyframes — not "0%, 100%".
# Keyframe colors are baked at generate time (GTK3 @keyframes often ignore CSS vars).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/theme-colors-lib.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$theme_dir"
out="$theme_dir/animations.generated.css"

# Resolve theme colors (preset merge when mode=preset), matching generate-theme-tokens.sh.
colors_json="$(waybar_theme_resolve_colors "$settings")"
rgba_from() { waybar_theme_color_with_alpha "$@"; }

critical="$(jq -rn --argjson c "$colors_json" '$c.critical // "#ff2a7f"')"
accent="$(jq -rn --argjson c "$colors_json" '$c.accent // "#00e5ff"')"
# Prefer solid cyan brand for idle glow when accent is translucent pink workspace pill.
ws_visible="$(jq -rn --argjson c "$colors_json" '$c.workspace_visible // empty')"
glow_accent="$accent"
if [[ -n "$ws_visible" ]]; then
  glow_accent="$ws_visible"
fi

crit_pulse0="$(rgba_from "$critical" "0.0" "rgba(255, 42, 127, 0.0)")"
crit_pulse1="$(rgba_from "$critical" "0.35" "rgba(255, 42, 127, 0.35)")"
crit_breathe_bg="$(rgba_from "$critical" "0.25" "rgba(255, 42, 127, 0.25)")"
crit_breathe_glow="$(rgba_from "$critical" "0.4" "rgba(255, 42, 127, 0.4)")"
accent_glow0="$(rgba_from "$glow_accent" "0.2" "rgba(0, 229, 255, 0.2)")"
accent_glow1="$(rgba_from "$glow_accent" "0.45" "rgba(0, 229, 255, 0.45)")"

# workspaces.slot_count: clamp 1–10, default 5.
slot_count="$(jq -r '.workspaces.slot_count // 5' "$settings" 2>/dev/null || echo 5)"
if [ "$slot_count" -lt 1 ] 2>/dev/null; then
  slot_count=5
fi
if [ "$slot_count" -gt 10 ] 2>/dev/null; then
  slot_count=10
fi

ws_active_sels=""
i=0
while [ "$i" -lt "$slot_count" ]; do
  if [ -n "$ws_active_sels" ]; then
    ws_active_sels+=",
"
  fi
  ws_active_sels+="#custom-ws-${i}.ws-active"
  i=$((i + 1))
done

workspace_pulse=$(jq -r '.visual.animations.workspace_pulse // false' "$settings")
critical_breathe=$(jq -r '.visual.animations.critical_breathe // false' "$settings")
idle_glow=$(jq -r '.visual.animations.idle_glow // false' "$settings")
reduced_mode=$(jq -r '.visual.animations.reduced_motion // "auto"' "$settings" | tr '[:upper:]' '[:lower:]')

# Force mode (or env) skips keyframe emission so generate stays deterministic without host probes.
case "${WAYBAR_REDUCED_MOTION:-}" in
  1 | true | TRUE | yes | YES | on | ON | reduce) reduced_mode=force ;;
esac
case "$reduced_mode" in
  force | always | on | true | 1)
    workspace_pulse=false
    critical_breathe=false
    idle_glow=false
    ;;
esac

{
  printf '%s\n\n' '/* Generated from visual.animations — do not edit by hand */'

  if [ "$reduced_mode" = "force" ] || [ "$reduced_mode" = "always" ] || [ "$reduced_mode" = "on" ] || [ "$reduced_mode" = "true" ] || [ "$reduced_mode" = "1" ]; then
    printf '%s\n' '/* reduced_motion=force — no CSS keyframe animations */'
  fi

  if [ "$workspace_pulse" = "true" ]; then
    cat <<EOF
/* Active workspace soft pulse (GTK3: from/to + alternate only) */
@keyframes waybar-workspace-pulse {
    from {
        box-shadow: 0 0 0 0 ${crit_pulse0};
    }
    to {
        box-shadow: 0 0 10px 2px ${crit_pulse1};
    }
}

${ws_active_sels},
#workspaces button.active {
    animation: waybar-workspace-pulse 2.4s ease-in-out infinite alternate;
}

EOF
  fi

  if [ "$critical_breathe" = "true" ]; then
    cat <<EOF
/* Critical modules breathe (generalizes security-blink) */
@keyframes waybar-critical-breathe {
    to {
        background-color: ${crit_breathe_bg};
        box-shadow: 0 0 12px ${crit_breathe_glow};
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
    cat <<EOF
/* Idle inhibitor soft cyan glow when active */
@keyframes waybar-idle-glow {
    from {
        box-shadow: 0 0 4px ${accent_glow0};
    }
    to {
        box-shadow: 0 0 12px ${accent_glow1};
    }
}

#idle_inhibitor.activated {
    animation: waybar-idle-glow 2.8s ease-in-out infinite alternate;
}

EOF
  fi
} >"$out"
