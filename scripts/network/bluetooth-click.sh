#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

mode="${1:-list}"

script_dir="${0%/*}"
# shellcheck source=waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

# shellcheck source=compositor-session.sh
if [ -f "$WAYBAR_SCRIPTS/lib/compositor-session.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
fi

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=rofi-popup-lib.sh
. "$WAYBAR_SCRIPTS/lib/rofi-popup-lib.sh"

open_bt_settings() {
  compositor=$(detect_compositor)

  case "$compositor" in
    kde)
      for cmd in systemsettings6 systemsettings; do
        if command -v "$cmd" >/dev/null 2>&1; then
          "$cmd" kcm_bluetooth &
          exit 0
        fi
      done
      if command -v kcmshell6 >/dev/null 2>&1; then
        kcmshell6 kcm_bluetooth &
        exit 0
      fi
      ;;
  esac

  if command -v blueman-manager >/dev/null 2>&1; then
    blueman-manager &
    exit 0
  fi

  if command -v bluetoothctl >/dev/null 2>&1; then
    term=$(_pick_terminal "$compositor")
    if [ -n "$term" ]; then
      _run_in_terminal "$term" bluetoothctl
      exit 0
    fi
    bluetoothctl
    exit 0
  fi

  notify-send "Bluetooth" "No bluetooth manager found" 2>/dev/null || true
}

get_bt_snapshot() {
  # Enforce timeout 2 to prevent slow/hanging bluetooth daemon calls from locking up Waybar
  show_out=$(timeout 2 bluetoothctl show 2>/dev/null || true)
  powered=$(printf '%s\n' "$show_out" | awk -F': ' '/Powered:/ {print $2; exit}') || true
  alias_name=$(printf '%s\n' "$show_out" | awk -F': ' '/Alias:/ {print $2; exit}') || true
  addr=$(printf '%s\n' "$show_out" | awk -F': ' '/Controller / {print $2; exit}') || true
  discoverable=$(printf '%s\n' "$show_out" | awk -F': ' '/Discoverable:/ {print $2; exit}') || true
  pairable=$(printf '%s\n' "$show_out" | awk -F': ' '/Pairable:/ {print $2; exit}') || true

  [ -z "$powered" ] && powered="no"
  [ -z "$alias_name" ] && alias_name="n/a"
  [ -z "$addr" ] && addr="n/a"
  [ -z "$discoverable" ] && discoverable="no"
  [ -z "$pairable" ] && pairable="no"

  connected_devs=$(timeout 2 bluetoothctl devices Connected 2>/dev/null || true)
  devices=$(timeout 2 bluetoothctl devices 2>/dev/null || true)
  device_rows=""
  connected_count=0

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    mac=$(printf '%s' "$line" | awk '{print $2}')
    name=$(printf '%s\n' "$line" | awk '{ $1=""; $2=""; sub(/^  */, ""); print }')
    [ -z "$mac" ] && continue
    [ -z "$name" ] && name="$mac"

    # Only run expensive info query if the device is actually connected
    is_connected=0
    if printf '%s\n' "$connected_devs" | grep -Fqi "$mac"; then
      is_connected=1
    fi

    if [ "$is_connected" -eq 1 ]; then
      info=$(timeout 2 bluetoothctl info "$mac" 2>/dev/null || true)
      connected=$(printf '%s\n' "$info" | awk -F': ' '/Connected:/ {print $2; exit}')
      paired=$(printf '%s\n' "$info" | awk -F': ' '/Paired:/ {print $2; exit}')
      trusted=$(printf '%s\n' "$info" | awk -F': ' '/Trusted:/ {print $2; exit}')
      # POSIX compliant match expression to parse battery percentage index
      batt=$(printf '%s\n' "$info" | awk '/Battery Percentage:/ { if (match($0, /\([0-9]+\)/)) { print substr($0, RSTART+1, RLENGTH-2); exit } }')

      [ -z "$connected" ] && connected="yes"
      [ -z "$paired" ] && paired="yes"
      [ -z "$trusted" ] && trusted="yes"
      [ -z "$batt" ] && batt="-"

      if [ "$connected" = "yes" ]; then
        connected_count=$((connected_count + 1))
      fi
    else
      connected="no"
      paired="yes"
      trusted="yes"
      batt="-"
    fi

    device_rows="$device_rows$mac|$name|$connected|$paired|$trusted|$batt
"
  done <<EOF
$devices
EOF

  header_full="$(format_header_row "Controller:" "$alias_name")
$(format_header_row "Address:" "$addr")
$(format_header_row "Power:" "$powered")
$(format_header_row "Connected devices:" "$connected_count")
$(format_header_row "Discoverable:" "$discoverable")
$(format_header_row "Pairable:" "$pairable")"

  header_compact="$(format_header_row "Controller:" "$alias_name")
$(format_header_row "Power:" "$powered")
$(format_header_row "Discoverable:" "$discoverable")
$(format_header_row "Connected devices:" "$connected_count")"

  printf '%s\n__SPLIT__\n%s\n__SPLIT__\n%s' "$header_compact" "$header_full" "$device_rows"
}

show_bt_popup() {
  header_compact="$1"
  header_full="$2"
  rows="$3"

  xoff_default="${WAYBAR_BT_DROPDOWN_X:--250}"
  yoff_default="${WAYBAR_BT_DROPDOWN_Y:-0}"
  popup_width_default="${WAYBAR_BT_DROPDOWN_WIDTH:-560}"
  popup_lines_default="${WAYBAR_BT_DROPDOWN_LINES:-16}"

  xoff=$(waybar_settings_get '.rofi.bluetooth.x_offset' "$xoff_default")
  yoff=$(waybar_settings_get '.rofi.bluetooth.y_offset' "$yoff_default")
  popup_width=$(waybar_settings_get '.rofi.bluetooth.width' "$popup_width_default")
  popup_lines=$(waybar_settings_get '.rofi.bluetooth.lines' "$popup_lines_default")

  if [ "${WAYBAR_BT_CLICK_NO_UI:-0}" = "1" ]; then
    printf 'Bluetooth\n%s\n\nDevices:\n%s\n' "$header_full" "$rows"
    return
  fi

  theme='
    window {
      width: WIDTH_PLACEHOLDER;
      location: northeast;
      anchor: northeast;
      x-offset: XOFF_PLACEHOLDER;
      y-offset: YOFF_PLACEHOLDER;
      border: 2px;
      border-color: #00e5ff;
      border-radius: 8px;
      background-color: #090b12f2;
    }
    mainbox {
      padding: 2px;
      background-color: transparent;
    }
    message {
      padding: 4px 10px 8px 10px;
      background-color: transparent;
      border: 0px;
      wrap: false;
    }
    textbox {
      text-color: #ff9df4;
      background-color: transparent;
    }
    inputbar {
      padding: 4px 8px;
      background-color: #0f1320;
      border: 0px;
      border-radius: 6px;
      margin: 0px 0px 2px 0px;
    }
    prompt {
      text-color: #ff4fd8;
      padding: 0px;
    }
    entry {
      text-color: #eaffff;
      placeholder: "Search devices...";
    }
    listview {
      lines: LINES_PLACEHOLDER;
      scrollbar: false;
      background-color: transparent;
      margin: 3px 0px 0px 0px;
      spacing: 1px;
    }
    element {
      padding: 4px 8px;
      border-radius: 4px;
      background-color: #0d111c;
      text-color: #d6f7ff;
    }
    element normal.normal {
      background-color: #0d111c;
      text-color: #d6f7ff;
    }
    element alternate.normal {
      background-color: #0a0e18;
      text-color: #d6f7ff;
    }
    element selected.normal {
      background-color: #1a1030;
      border: 1px;
      border-color: #ff4fd8;
      text-color: #ffffff;
    }
    element-text {
      background-color: transparent;
      text-color: inherit;
    }
  '

  theme=$(printf '%s' "$theme" | sed "s/WIDTH_PLACEHOLDER/$popup_width/; s/LINES_PLACEHOLDER/$popup_lines/; s/XOFF_PLACEHOLDER/$xoff/; s/YOFF_PLACEHOLDER/$yoff/")

  tmpdir=$(mktemp -d)
  printf '%s' "$header_compact" >"$tmpdir/header_compact"
  printf '%s' "$header_full" >"$tmpdir/header_full"
  printf '%s' "$rows" >"$tmpdir/rows"

  rofi -show bt-popup \
    -modi "bt-popup:$0 __bt_rofi $tmpdir" \
    -me-select-entry '' -me-accept-entry MousePrimary \
    -kb-custom-1 "Alt+m" -kb-custom-2 "Alt+p" -kb-custom-3 "Alt+d" -kb-custom-4 "Alt+c" \
    -theme-str "$theme" \
    >/dev/null 2>&1 || true

  rm -rf "$tmpdir"
}

bt_popup_rofi() {
  tmpdir="$1"
  [ -d "$tmpdir" ] || exit 0

  header_compact=$(cat "$tmpdir/header_compact")
  header_full=$(cat "$tmpdir/header_full")
  rows=$(cat "$tmpdir/rows")

  expanded=0
  clear_requested=0
  state="${ROFI_DATA:-expanded=0}"
  for kv in $(printf '%s' "$state" | tr ';' ' '); do
    key=${kv%%=*}
    val=${kv#*=}
    case "$key" in
      expanded) expanded="$val" ;;
    esac
  done

  case "${ROFI_RETV:-0}" in
    10)
      if [ "$expanded" = "1" ]; then expanded=0; else expanded=1; fi
      ;;
    11)
      # Toggle Bluetooth power quickly.
      powered=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/ {print $2; exit}') || true
      if [ "$powered" = "yes" ]; then
        bluetoothctl power off >/dev/null 2>&1 || true
      else
        bluetoothctl power on >/dev/null 2>&1 || true
      fi
      snap=$(get_bt_snapshot)
      header_compact=$(printf '%s' "$snap" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==0 {print}')
      header_full=$(printf '%s' "$snap" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==1 {print}')
      rows=$(printf '%s' "$snap" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==2 {print}')
      ;;
    12)
      # Toggle discoverable mode.
      discoverable=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Discoverable:/ {print $2; exit}') || true
      if [ "$discoverable" = "yes" ]; then
        bluetoothctl discoverable off >/dev/null 2>&1 || true
      else
        bluetoothctl discoverable on >/dev/null 2>&1 || true
      fi
      snap=$(get_bt_snapshot)
      header_compact=$(printf '%s' "$snap" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==0 {print}')
      header_full=$(printf '%s' "$snap" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==1 {print}')
      rows=$(printf '%s' "$snap" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==2 {print}')
      ;;
    13)
      clear_requested=1
      ;;
    1)
      action="${ROFI_INFO:-}"
      case "$action" in
        connect:*)
          mac=${action#connect:}
          bluetoothctl connect "$mac" >/dev/null 2>&1 || true
          notify-send "Bluetooth" "Connecting to $mac" 2>/dev/null || true
          printf '\0quit\x1ftrue\n'
          exit 0
          ;;
        disconnect:*)
          mac=${action#disconnect:}
          bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
          notify-send "Bluetooth" "Disconnecting $mac" 2>/dev/null || true
          printf '\0quit\x1ftrue\n'
          exit 0
          ;;
      esac
      ;;
  esac

  header="$header_compact"
  details_state="Compact"
  if [ "$expanded" = "1" ]; then
    header="$header_full"
    details_state="Full"
  fi

  header_display=$(escape_markup "$header" | awk 'BEGIN{ORS=""} {if (NR>1) printf "&#10;"; printf "%s", $0}')
  hint_l1=$(format_hints_row "[Alt+M] Details: $details_state" "Power [Alt+P]")
  hint_l2=$(format_hints_row "[Alt+C] Clear Search" "Discoverable [Alt+D]")
  hint_l1=$(escape_markup "$hint_l1")
  hint_l2=$(escape_markup "$hint_l2")

  sep=$(escape_markup "-------------- Available Devices --------------")
  message_markup="$header_display&#10;<span foreground='#8aa2c5'>$hint_l1</span>&#10;<span foreground='#8aa2c5'>$hint_l2</span>&#10;<span foreground='#76819a'>$sep</span>"

  printf '\0prompt\x1fBluetooth\n'
  printf '\0message\x1f%s\n' "$message_markup"
  printf '\0no-custom\x1ftrue\n'
  printf '\0use-hot-keys\x1ftrue\n'
  printf '\0markup-rows\x1ftrue\n'
  if [ "$clear_requested" = "1" ]; then
    printf '\0keep-selection\x1ftrue\n'
  fi
  printf '\0data\x1fexpanded=%s\n' "$expanded"

  while IFS='|' read -r mac name connected paired trusted batt; do
    [ -n "$mac" ] || continue
    [ -n "$name" ] || name="$mac"

    status="paired:$paired trusted:$trusted batt:$batt"
    line="$name [$status]"
    escaped_line=$(escape_markup "$line")

    if [ "$connected" = "yes" ]; then
      display="<span foreground='#2cffb0' weight='bold'>* ${escaped_line}</span>"
      printf '%s\0display\x1f%s\x1finfo\x1fdisconnect:%s\n' "$line" "$display" "$mac"
    else
      printf '%s\0display\x1f%s\x1finfo\x1fconnect:%s\n' "$line" "$escaped_line" "$mac"
    fi
  done <<EOF
$rows
EOF
}

[ "$mode" = "manage" ] && {
  open_bt_settings
  exit 0
}
[ "$mode" = "toggle" ] && {
  if bluetoothctl show | rg -Fq "Powered: yes"; then
    bluetoothctl power off
  else
    bluetoothctl power on
  fi
  exit 0
}
[ "$mode" = "__bt_rofi" ] && {
  bt_popup_rofi "$2"
  exit 0
}

if ! command -v bluetoothctl >/dev/null 2>&1; then
  notify-send "Bluetooth" "bluetoothctl not found" 2>/dev/null || true
  exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
  notify-send "Bluetooth" "rofi not found" 2>/dev/null || true
  exit 1
fi

snapshot=$(get_bt_snapshot)
header_compact=$(printf '%s' "$snapshot" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==0 {print}')
header_full=$(printf '%s' "$snapshot" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==1 {print}')
rows=$(printf '%s' "$snapshot" | awk 'BEGIN{p=0} /__SPLIT__/ {p++; next} p==2 {print}')

show_bt_popup "$header_compact" "$header_full" "$rows"
