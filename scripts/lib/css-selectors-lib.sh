#!/usr/bin/env bash
# Shared CSS selector helpers for Waybar generators (bash only).
# Source from generate-*.sh after WAYBAR_SCRIPTS is set.

# Clamp integer: waybar_css_clamp_int VALUE DEFAULT MIN MAX
waybar_css_clamp_int() {
  local val="${1:-}"
  local default="$2"
  local min="$3"
  local max="$4"
  if [[ ! "$val" =~ ^[0-9]+$ ]]; then
    val="$default"
  fi
  if [[ "$val" -lt "$min" ]]; then
    val="$min"
  fi
  if [[ "$val" -gt "$max" ]]; then
    val="$max"
  fi
  printf '%s' "$val"
}

# Read slot_count from settings JSON: waybar_css_slot_count SETTINGS_PATH KEY DEFAULT MIN MAX
waybar_css_slot_count() {
  local settings="$1"
  local key="$2"
  local default="$3"
  local min="$4"
  local max="$5"
  local raw="$default"
  if [[ -f "$settings" ]] && command -v jq >/dev/null 2>&1; then
    raw="$(jq -r --arg k "$key" --argjson d "$default" '.[$k].slot_count // $d' "$settings" 2>/dev/null || echo "$default")"
  fi
  waybar_css_clamp_int "$raw" "$default" "$min" "$max"
}

# Emit comma-separated #prefixN$suffix for 0..count-1
# waybar_css_id_range PREFIX COUNT [SUFFIX]
waybar_css_id_range() {
  local prefix="$1"
  local count="$2"
  local suffix="${3:-}"
  local i
  for ((i = 0; i < count; i++)); do
    if [[ "$i" -gt 0 ]]; then
      printf ',\n'
    fi
    printf '%s%s%s' "$prefix" "$i" "$suffix"
  done
}

# Shared pill module IDs (layout + semantic chrome). One ID per line.
# Real Waybar idle widget is #idle_inhibitor (underscore).
waybar_css_pill_ids() {
  cat <<'EOF'
#custom-active-window
#window
#mpris
#custom-mpris
#pulseaudio
#network.bond
#network.bandwidthUpBytes
#network.bandwidthDownBytes
#network.eno1
#network.enp5s0
#network.wlan0
#custom-eno1
#custom-enp5s0
#custom-wlan0
#custom-vpnstatus
#bluetooth
#custom-powerprofiles
#custom-asusctl
#custom-brightness
#custom-tailscale
#custom-notifications
#custom-screenshot
#custom-screenrecord
#custom-clipboard
#custom-mic
#custom-docker
#custom-runtimes
#custom-updates
#custom-nightlight
#custom-cpu
#custom-gpu
#custom-memory
#custom-disk
#custom-nvme
#custom-psu
#custom-fans
#custom-liquidctl
#custom-coolercontrol
#custom-openlinkhub
#custom-stats-carousel
#custom-ups
#custom-dock-browser
#custom-dock-helium
#custom-dock-pear
#custom-dock-floorp
#custom-dock-cursor
#custom-dock-vscode
#custom-dock-zed
#custom-dock-kitty
#custom-dock-terminal
#custom-dock-files
#custom-dock-obsidian
#custom-dock-krita
#custom-dock-orcaslicer
#custom-dock-discord
#custom-dock-steam
#custom-dock-heroic
#custom-dock-lutris
#custom-dock-anyrun
#custom-dock-windows
#taskbar
#clock
#clock.bottom
#tray
#idle_inhibitor
#custom-hyprwhspr
#custom-hyprnotify
#custom-hyprlight
#custom-discord
#custom-keyboard-layout
#custom-kdeconnect
#custom-device-notifier
#custom-device-battery
#custom-streamdeck
#custom-colorpicker
#custom-rgb
#custom-vaults
#custom-touchpad
#custom-gamemode
#custom-keybindhint
#custom-privacy-screenshare
#custom-privacy-webcam
#custom-privacy-audio-in
#custom-privacy-audio-out
#custom-privacy-location
#custom-lock
#custom-power-menu
#custom-logout
#custom-suspend
#custom-reboot
#custom-shutdown
#custom-cava
#custom-pomodoro
#custom-homelab
#custom-github
#custom-weather
#custom-systemd
#custom-uptime
#custom-syncthing
#custom-sunshine
#custom-i2pd
#custom-yggdrasil
#custom-ipfs
#custom-libredefender
#custom-chkrootkit
#custom-media-prev
#custom-media-next
EOF
}

# Pill :hover set — same as pills, plus #submap, minus power specialty (own hovers).
waybar_css_pill_hover_ids() {
  waybar_css_pill_ids | awk '
    BEGIN { print "#submap" }
    /^#custom-(lock|power-menu|logout|suspend|reboot|shutdown)$/ { next }
    { print }
  '
}

# Emit comma-separated selectors from newline-separated IDs on stdin.
# Optional suffix (e.g. ":hover") appended to each ID.
waybar_css_emit_selector_list() {
  local suffix="${1:-}"
  local first=1
  local id
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      printf ',\n'
    fi
    printf '%s%s' "$id" "$suffix"
  done
}

# Drawer side keys (match drawers.icons + generate-drawers-modules handles).
waybar_css_drawer_sides() {
  cat <<'EOF'
desk
devices
dock
tray
media
net
tools
infra
hardware
cooling
power
privacy
security
EOF
}

# Map drawer side → Waybar group id (desk/tray/dock special; others 1:1).
waybar_css_drawer_group_for_side() {
  case "$1" in
    desk) printf 'desk-controls' ;;
    tray) printf 'tray-apps' ;;
    dock) printf 'dock-apps' ;;
    *) printf '%s' "$1" ;;
  esac
}

# #custom-*-drawer selectors for every drawer side.
waybar_css_drawer_handle_ids() {
  local side
  while IFS= read -r side; do
    [[ -z "$side" ]] && continue
    printf '#custom-%s-drawer\n' "$side"
  done < <(waybar_css_drawer_sides)
}

# Accent-colored handles (power uses critical specialty styling).
waybar_css_drawer_accent_handle_ids() {
  waybar_css_drawer_handle_ids | grep -v '^#custom-power-drawer$'
}

# Drawer group shells (plus top-status nest that is not a drawer side).
waybar_css_drawer_group_shell_ids() {
  local side
  while IFS= read -r side; do
    [[ -z "$side" ]] && continue
    printf '#%s\n' "$(waybar_css_drawer_group_for_side "$side")"
  done < <(waybar_css_drawer_sides)
  printf '#top-status\n'
}

# Groups that hide .drawer-child when collapsed (exclude top-status nest).
waybar_css_drawer_child_hide_group_ids() {
  waybar_css_drawer_group_shell_ids | grep -v '^#top-status$'
}

# Non-drawer pill clusters (layout + semantic group chrome).
waybar_css_cluster_group_ids() {
  cat <<'EOF'
#center
#status
EOF
}
