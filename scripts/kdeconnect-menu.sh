#!/usr/bin/env bash
# Interactive Rofi menu for KDE Connect actions.
set -euo pipefail

script_dir="$(dirname "$0")"
if [ -f "$script_dir/waybar-settings.sh" ]; then
  . "$script_dir/waybar-settings.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-settings.sh"
fi

# Query available devices
devices=()
device_ids=()
device_names=()
kde_width=$(waybar_settings_get '.rofi.kdeconnect.width' '400')
file_width=$((kde_width + 200))
[ "$file_width" -lt 600 ] && file_width=600

# kdeconnect-cli -a --id-name-only prints format:
# <device_id> <device_name>
while read -r line; do
  [ -z "$line" ] && continue
  id=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | cut -d' ' -f2-)
  if [ -n "$id" ] && [ -n "$name" ]; then
    device_ids+=("$id")
    device_names+=("$name")
  fi
done < <(kdeconnect-cli -a --id-name-only 2>/dev/null || true)

num_devices=${#device_ids[@]}

if [ "$num_devices" -eq 0 ]; then
  notify-send "KDE Connect" "No reachable devices found."
  exit 0
fi

target_device_id=""
target_device_name=""

if [ "$num_devices" -eq 1 ]; then
  target_device_id="${device_ids[0]}"
  target_device_name="${device_names[0]}"
else
  # Show rofi menu to select device
  selected_dev=$(printf "%s\n" "${device_names[@]}" | rofi -dmenu -p "Select Device" -theme-str "window {width: ${kde_width}px;}")
  [ -z "$selected_dev" ] && exit 0
  
  for i in "${!device_names[@]}"; do
    if [ "${device_names[$i]}" = "$selected_dev" ]; then
      target_device_id="${device_ids[$i]}"
      target_device_name="${device_names[$i]}"
      break
    fi
  done
fi

[ -z "$target_device_id" ] && exit 0

# Show actions for the selected device
actions=(
  "󰂚 Ring Device"
  "󰏲 Send Ping"
  "󰲸 Share Clipboard"
  "󰄬 Send File"
  "󰉋 Mount Storage"
  "󰍜 Unmount Storage"
)

selected_action=$(printf "%s\n" "${actions[@]}" | rofi -dmenu -p "Action ($target_device_name)" -theme-str "window {width: ${kde_width}px;}")
[ -z "$selected_action" ] && exit 0

case "$selected_action" in
  *"Ring Device"*)
    kdeconnect-cli -d "$target_device_id" --ring >/dev/null 2>&1 || true
    ;;
  *"Send Ping"*)
    kdeconnect-cli -d "$target_device_id" --ping >/dev/null 2>&1 || true
    ;;
  *"Share Clipboard"*)
    if command -v wl-paste >/dev/null 2>&1; then
      clip_text=$(wl-paste)
      if [ -n "$clip_text" ]; then
        kdeconnect-cli -d "$target_device_id" --share-text "$clip_text" >/dev/null 2>&1 || true
        notify-send "KDE Connect" "Clipboard shared with $target_device_name."
      else
        notify-send "KDE Connect" "Clipboard is empty."
      fi
    else
      notify-send "KDE Connect" "Error: wl-paste utility not found."
    fi
    ;;
  *"Send File"*)
    if command -v zenity >/dev/null 2>&1; then
      file_path=$(zenity --file-selection --title="Select File to Send to $target_device_name")
      if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        kdeconnect-cli -d "$target_device_id" --share "$file_path" >/dev/null 2>&1 || true
        notify-send "KDE Connect" "Sending file to $target_device_name..."
      fi
    else
      file_path=$(rofi -dmenu -p "Enter File Path" -theme-str "window {width: ${file_width}px;}")
      if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        kdeconnect-cli -d "$target_device_id" --share "$file_path" >/dev/null 2>&1 || true
        notify-send "KDE Connect" "Sending file to $target_device_name..."
      else
        notify-send "KDE Connect" "File not found or action cancelled."
      fi
    fi
    ;;
  *"Mount Storage"*)
    kdeconnect-cli -d "$target_device_id" --mount >/dev/null 2>&1 || true
    mount_point=$(kdeconnect-cli -d "$target_device_id" --get-mount-point 2>/dev/null || echo "")
    if [ -n "$mount_point" ]; then
      notify-send "KDE Connect" "Mounted device storage at $mount_point."
    else
      notify-send "KDE Connect" "Device storage mounted."
    fi
    ;;
  *"Unmount Storage"*)
    mount_point=$(kdeconnect-cli -d "$target_device_id" --get-mount-point 2>/dev/null || echo "")
    if [ -n "$mount_point" ]; then
      fusermount -u "$mount_point" >/dev/null 2>&1 || umount "$mount_point" >/dev/null 2>&1 || true
      notify-send "KDE Connect" "Unmounted device storage."
    else
      notify-send "KDE Connect" "Device storage unmounted."
    fi
    ;;
esac
