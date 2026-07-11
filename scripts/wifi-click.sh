#!/usr/bin/env bash
set -eu

script_dir="${0%/*}"
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi

# shellcheck source=compositor-session.sh
if [ -f "$script_dir/compositor-session.sh" ]; then
  . "$script_dir/compositor-session.sh"
fi

if [ -f "$script_dir/waybar-settings.sh" ]; then
  . "$script_dir/waybar-settings.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-settings.sh"
fi

mode="${1:-list}"
iface="${2:-wlan0}"

# ---------------------------------------------------------------------------
# Rofi popup styled to match waybar.  On selection, connect to that network.
# ---------------------------------------------------------------------------
show_wifi_popup() {
  header_compact_masked="$1"
  header_full_masked="$2"
  header_compact_clear="$3"
  header_full_clear="$4"
  items="$5"
  # Keep popup visually attached to the Wi-Fi module by default.
  xoff_default="${WAYBAR_WIFI_DROPDOWN_X:--270}"
  yoff_default="${WAYBAR_WIFI_DROPDOWN_Y:-0}"
  popup_width_default="${WAYBAR_WIFI_DROPDOWN_WIDTH:-560}"
  popup_lines_default="${WAYBAR_WIFI_DROPDOWN_LINES:-20}"

  xoff=$(waybar_settings_get '.rofi.wifi.x_offset' "$xoff_default")
  yoff=$(waybar_settings_get '.rofi.wifi.y_offset' "$yoff_default")
  popup_width=$(waybar_settings_get '.rofi.wifi.width' "$popup_width_default")
  popup_lines=$(waybar_settings_get '.rofi.wifi.lines' "$popup_lines_default")

  if [ "${WAYBAR_WIFI_CLICK_NO_UI:-0}" = "1" ]; then
    printf 'Wi-Fi Networks\n%s\n\nNearby networks:\n%s\n' "$header_full_masked" "$items"
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
      placeholder: "Search networks...";
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
  printf '%s' "$header_compact_masked" > "$tmpdir/header_compact_masked"
  printf '%s' "$header_full_masked" > "$tmpdir/header_full_masked"
  printf '%s' "$header_compact_clear" > "$tmpdir/header_compact_clear"
  printf '%s' "$header_full_clear" > "$tmpdir/header_full_clear"
  printf '%s' "$items" > "$tmpdir/items"
  printf '%s' "$theme" > "$tmpdir/theme"

  # Rofi Custom Script Mode (Script-Modi):
  # Rofi allows external scripts to act as dynamic interactive menus.
  # We run rofi with "-modi <name>:<script>", which executes this script in a loop.
  # On each interaction (keypress, selection, hotkey), Rofi runs this script,
  # passing the return code in ROFI_RETV and previous state strings in ROFI_DATA.
  rofi -show wifi-popup \
       -modi "wifi-popup:$0 __wifi_rofi $tmpdir $iface" \
      -me-select-entry '' -me-accept-entry MousePrimary \
      -kb-custom-1 "Alt+m" -kb-custom-2 "Alt+s" -kb-custom-3 "Alt+c" -kb-custom-4 "Alt+d" \
       -theme-str "$theme" \
       >/dev/null 2>&1 || true

  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
format_header_row() {
  label="$1"
  value="$2"
  width="${3:-52}"
  awk -v l="$label" -v v="$value" -v w="$width" 'BEGIN {
    pad = w - length(l) - length(v)
    if (pad < 1) pad = 1
    printf "%s%*s%s", l, pad, "", v
  }'
}

# ---------------------------------------------------------------------------
format_hints_row() {
  hint1="$1"
  hint2="$2"
  width="${3:-52}"
  awk -v h1="$hint1" -v h2="$hint2" -v w="$width" 'BEGIN {
    pad = w - length(h1) - length(h2)
    if (pad < 1) pad = 1
    printf "%s%*s%s", h1, pad, "", h2
  }'
}

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
wifi_popup_rofi() {
  tmpdir="$1"
  ui_iface="$2"

  [ -d "$tmpdir" ] || exit 0

  header_compact_masked=$(cat "$tmpdir/header_compact_masked")
  header_full_masked=$(cat "$tmpdir/header_full_masked")
  header_compact_clear=$(cat "$tmpdir/header_compact_clear")
  header_full_clear=$(cat "$tmpdir/header_full_clear")
  items=$(cat "$tmpdir/items")

  expanded=0
  sensitive_shown=0
  sensitive_armed=0
  clear_requested=0
  
  # Restore UI state between Rofi executions:
  # Rofi starts a new process on each keypress. We preserve state by reading
  # and deserializing the ROFI_DATA variable (which we printed in a previous iteration).
  state="${ROFI_DATA:-expanded=0;sensitive=0;armed=0}"
  for kv in $(printf '%s' "$state" | tr ';' ' '); do
    key=${kv%%=*}
    val=${kv#*=}
    case "$key" in
      expanded) expanded="$val" ;;
      sensitive) sensitive_shown="$val" ;;
      armed) sensitive_armed="$val" ;;
    esac
  done

  # Process Rofi Return Code (ROFI_RETV):
  # RETV indicates how the script was invoked:
  #   0 = Initial load
  #   1 = Row selected (Enter key)
  #   10 = Custom 1 (Alt+M: toggle detail view expansion)
  #   11 = Custom 2 (Alt+S: toggle sensitive info mask)
  #   12 = Custom 3 (Alt+C: clear search)
  #   13 = Custom 4 (Alt+D: disarm safety lock)
  case "${ROFI_RETV:-0}" in
    10)
      if [ "$expanded" = "1" ]; then expanded=0; else expanded=1; fi
      sensitive_armed=0
      ;;
    11)
      if [ "$sensitive_shown" = "1" ]; then
        sensitive_shown=0
        sensitive_armed=0
      else
        if [ "$sensitive_armed" = "1" ]; then
          sensitive_shown=1
          sensitive_armed=0
        else
          sensitive_armed=1
        fi
      fi
      ;;
    12)
      sensitive_armed=0
      clear_requested=1
      ;;
    13)
      sensitive_armed=0
      clear_requested=1
      ;;
    1)
    action="${ROFI_INFO:-}"
    case "$action" in
      connect:*)
        sel_ssid=${action#connect:}
        if [ -n "$sel_ssid" ] && [ "$sel_ssid" != "<hidden>" ]; then
          cur_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$ui_iface" 2>/dev/null \
            | awk -F: 'NR==1 { sub(/^[^:]*:/, ""); print; exit }') || true
          [ "$cur_ssid" = "--" ] && cur_ssid=""
          if [ "$sel_ssid" != "$cur_ssid" ]; then
            notify-send "Wi-Fi" "Connecting to $sel_ssid…" 2>/dev/null || true
            # Launch connection in background so Rofi is not blocked while waiting for handshakes
            nmcli dev wifi connect "$sel_ssid" ifname "$ui_iface" >/dev/null 2>&1 &
          fi
        fi
        printf '\0quit\x1ftrue\n'
        exit 0
        ;;
    esac
    ;;
  esac

  header="$header_compact_masked"
  if [ "$sensitive_shown" = "1" ]; then
    header="$header_compact_clear"
  fi
  expand_label="▸ Show more info"
  if [ "$expanded" = "1" ]; then
    header="$header_full_masked"
    if [ "$sensitive_shown" = "1" ]; then
      header="$header_full_clear"
    fi
    expand_label="▾ Show less info"
  fi

  sensitive_label="🔒 Sensitive: hidden"
  if [ "$sensitive_shown" = "1" ]; then
    sensitive_label="🔓 Sensitive: shown (click to mask)"
  elif [ "$sensitive_armed" = "1" ]; then
    sensitive_label="⚠ Click again: show sensitive"
  fi

  header_display=$(escape_markup "$header" | awk 'BEGIN{ORS=""} {if (NR>1) printf "&#10;"; printf "%s", $0}')
  details_state='Full'
  [ "$expanded" = "0" ] && details_state='Compact'

  sensitive_state='Hidden'
  if [ "$sensitive_shown" = "1" ]; then
    sensitive_state='Shown'
  elif [ "$sensitive_armed" = "1" ]; then
    sensitive_state='Armed'
  fi

  hint_l1=$(format_hints_row "[Alt+M] Details: $details_state" "Sensitive: $sensitive_state [Alt+S]")
  hint_l2=$(format_hints_row "[Alt+C] Clear Search" "Disarm [Alt+D]")
  hint_l1=$(escape_markup "$hint_l1")
  hint_l2=$(escape_markup "$hint_l2")
  separator_line='────────────── Available Networks ──────────────'
  separator_line=$(escape_markup "$separator_line")
  message_markup="$header_display&#10;<span foreground='#8aa2c5'>$hint_l1</span>&#10;<span foreground='#8aa2c5'>$hint_l2</span>&#10;<span foreground='#76819a'>$separator_line</span>"

  printf '\0prompt\x1f󰤨 Wi-Fi\n'
  printf '\0message\x1f%s\n' "$message_markup"
  printf '\0no-custom\x1ftrue\n'
  printf '\0use-hot-keys\x1ftrue\n'
  printf '\0markup-rows\x1ftrue\n'
  if [ "$clear_requested" = "1" ]; then
    # Re-render while clearing current filter text.
    printf '\0keep-selection\x1ftrue\n'
  fi
  printf '\0data\x1fexpanded=%s;sensitive=%s;armed=%s\n' "$expanded" "$sensitive_shown" "$sensitive_armed"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ssid=$(printf '%s\n' "$line" | awk '{sub(/^[* ]+/, ""); sub(/ \([0-9]+%,.*/, ""); print}')
    escaped_line=$(escape_markup "$line")
    if [ "$ssid" = "<hidden>" ]; then
      printf '%s\0display\x1f%s\x1finfo\x1fnoop\n' "$line" "$escaped_line"
    else
      display_line="$escaped_line"
      case "$line" in
        "* "*)
          display_line="<span foreground='#2cffb0' weight='bold'>${escaped_line}</span>"
          ;;
      esac
      printf '%s\0display\x1f%s\x1finfo\x1fconnect:%s\n' "$line" "$display_line" "$ssid"
    fi
  done <<EOF
$items
EOF
}

# ---------------------------------------------------------------------------

open_settings() {
  compositor=$(detect_compositor)

  case "$compositor" in
    kde)
      for cmd in systemsettings6 systemsettings; do
        if command -v "$cmd" >/dev/null 2>&1; then
          "$cmd" kcm_networkmanagement &
          exit 0
        fi
      done
      ;;
    hyprland)
      if command -v nm-connection-editor >/dev/null 2>&1; then
        nm-connection-editor &
        exit 0
      fi
      ;;
  esac

  if command -v nmtui >/dev/null 2>&1; then
    term=$(_pick_terminal "$compositor")
    if [ -n "$term" ]; then
      _run_in_terminal "$term" nmtui
      exit 0
    fi
    nmtui
    exit 0
  fi

  notify-send "Wi-Fi" "No network settings app found" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
get_external_ip() {
  ip=""

  if command -v curl >/dev/null 2>&1; then
    for url in \
      "https://api64.ipify.org?format=text" \
      "https://ifconfig.me/ip" \
      "https://icanhazip.com" \
      "https://checkip.amazonaws.com"
    do
      ip=$(curl -fsS --connect-timeout 2 --max-time 4 "$url" 2>/dev/null \
        | tr -d '\r' \
        | awk 'NR==1 {gsub(/[[:space:]]/, ""); print; exit}')
      [ -n "$ip" ] && { printf '%s' "$ip"; return 0; }
    done
  fi

  if command -v wget >/dev/null 2>&1; then
    for url in \
      "https://api64.ipify.org?format=text" \
      "https://ifconfig.me/ip" \
      "https://icanhazip.com" \
      "https://checkip.amazonaws.com"
    do
      ip=$(wget -qO- --timeout=4 "$url" 2>/dev/null \
        | tr -d '\r' \
        | awk 'NR==1 {gsub(/[[:space:]]/, ""); print; exit}')
      [ -n "$ip" ] && { printf '%s' "$ip"; return 0; }
    done
  fi

  return 1
}

# ---------------------------------------------------------------------------
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
mkdir -p "$cache_dir"

cache_fresh() {
  file="$1"
  max_age="$2"
  [ -f "$file" ] || return 1
  age=$(cache_file_age "$file")
  [ "$age" -le "$max_age" ] 2>/dev/null
}

get_external_ip_fast() {
  ip_cache="$cache_dir/wifi_ext_ip.txt"
  if cache_fresh "$ip_cache" 900; then
    cat "$ip_cache"
    return 0
  fi

  if [ -f "$ip_cache" ]; then
    # Stale value is better than blocking UI startup.
    cat "$ip_cache"
  fi

  (
    ip=$(get_external_ip || true)
    if [ -n "$ip" ]; then
      tmp_ip="$ip_cache.tmp.$$"
      printf '%s' "$ip" > "$tmp_ip"
      mv -f "$tmp_ip" "$ip_cache"
    fi
  ) >/dev/null 2>&1 &

  return 0
}

get_latency_fast() {
  gw="$1"
  lat_cache="$cache_dir/wifi_latency_${iface}.txt"

  if cache_fresh "$lat_cache" 60; then
    cat "$lat_cache"
    return 0
  fi

  if [ -f "$lat_cache" ]; then
    cat "$lat_cache"
  fi

  (
    l=""
    w=""
    if command -v ping >/dev/null 2>&1; then
      if [ -n "$gw" ]; then
        l=$(ping -n -c 1 -W 1 "$gw" 2>/dev/null \
          | sed -n 's/.*time=\([0-9.]*\).*/\1 ms/p') || true
      fi
      w=$(ping -n -c 1 -W 1 1.1.1.1 2>/dev/null \
        | sed -n 's/.*time=\([0-9.]*\).*/\1 ms/p') || true
    fi
    tmp_lat="$lat_cache.tmp.$$"
    printf '%s|%s' "$l" "$w" > "$tmp_lat"
    mv -f "$tmp_lat" "$lat_cache"
  ) >/dev/null 2>&1 &

  return 0
}

# ---------------------------------------------------------------------------
[ "$mode" = "__wifi_rofi" ] && { wifi_popup_rofi "$2" "${3:-wlan0}"; exit 0; }
[ "$mode" = "manage" ] && { open_settings; exit 0; }
[ "$mode" = "toggle" ] && {
  if nmcli radio wifi | rg -Fq enabled; then
    nmcli radio wifi off
  else
    nmcli radio wifi on
  fi
  exit 0
}

if ! command -v nmcli >/dev/null 2>&1; then
  notify-send "Wi-Fi" "nmcli not found" 2>/dev/null || true
  exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
  notify-send "Wi-Fi" "rofi not found" 2>/dev/null || true
  exit 1
fi

active_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$iface" 2>/dev/null \
  | awk -F: 'NR==1 { sub(/^[^:]*:/, ""); print; exit }') || true
[ "$active_ssid" = "--" ] && active_ssid=""
ip4=$(nmcli -t -f IP4.ADDRESS dev show "$iface" 2>/dev/null | awk -F: 'NR==1 {print $2; exit}') || true
gateway=$(ip -4 route show default dev "$iface" 2>/dev/null | awk '/default/ {print $3; exit}') || true
ext_ip=$(get_external_ip_fast || true)

dns=$(nmcli -t -f IP4.DNS dev show "$iface" 2>/dev/null \
  | awk -F: 'NF { if ($2 != "") { if (out) out=out", "$2; else out=$2 } } END { print out }') || true

wifi_meta=$(nmcli -t -f IN-USE,CHAN,RATE,SIGNAL dev wifi list ifname "$iface" --rescan no 2>/dev/null \
  | awk -F: '$1=="*" {print $2"|"$3"|"$4; exit}') || true
if [ -z "$wifi_meta" ]; then
  wifi_meta=$(nmcli -t -f IN-USE,CHAN,RATE,SIGNAL dev wifi list ifname "$iface" 2>/dev/null \
    | awk -F: '$1=="*" {print $2"|"$3"|"$4; exit}') || true
fi
old_ifs=$IFS
IFS='|'
set -- $wifi_meta
IFS=$old_ifs
chan="${1:-}"
rate="${2:-}"
signal="${3:-}"

band=""
if [ -n "$chan" ]; then
  case "$chan" in
    ''|*[!0-9]*) band="" ;;
    *)
      if [ "$chan" -le 14 ]; then
        band="2.4GHz"
      elif [ "$chan" -ge 1 ]; then
        band="5GHz+"
      fi
      ;;
  esac
fi

vpn_status="Off"
if nmcli -t -f TYPE,STATE connection show --active 2>/dev/null \
  | awk -F: '$1=="vpn" && $2=="activated" {found=1} END{exit found?0:1}'
then
  vpn_status="On"
fi

lat_pair=$(get_latency_fast "$gateway" || true)
old_ifs=$IFS
IFS='|'
set -- $lat_pair
IFS=$old_ifs
lan_rtt="${1:-}"
wan_rtt="${2:-}"

scan=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list ifname "$iface" --rescan no 2>/dev/null \
  | awk 'NR<=50' || true)

# Fast path uses cached scan data. If it only has the active AP (or none), do a full refresh.
scan_count=$(printf '%s\n' "$scan" | awk 'NF{n++} END{print n+0}')
if [ "$scan_count" -le 1 ]; then
  scan=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list ifname "$iface" 2>/dev/null \
    | awk 'NR<=50' || true)
fi

if [ -z "$scan" ]; then
  notify-send "Wi-Fi" "No scan data for $iface" 2>/dev/null || true
  exit 0
fi

# Deduplicate by SSID: active entry always wins; for others keep highest signal.
# Output: active entries first, then remaining sorted by signal descending.
list=$(printf '%s\n' "$scan" | awk -F: '
{
  active = ($1 == "*")
  ssid   = ($2 == "") ? "<hidden>" : $2
  signal = ($3+0)
  sec    = ($4 == "") ? "open" : $4

  if (active) {
    best_active[ssid]     = signal
    best_sec_active[ssid] = sec
  } else if (!(ssid in best_sig) || signal > best_sig[ssid]) {
    best_sig[ssid] = signal
    best_sec[ssid] = sec
  }
}
END {
  for (ssid in best_active) {
    printf "* %s (%d%%, %s)\n", ssid, best_active[ssid], best_sec_active[ssid]
    delete best_sig[ssid]
  }
  n = 0
  for (ssid in best_sig) {
    sigs[n] = best_sig[ssid]; ssids[n] = ssid; secs[n] = best_sec[ssid]; n++
  }
  for (i = 0; i < n-1; i++)
    for (j = i+1; j < n; j++)
      if (sigs[j] > sigs[i]) {
        t=sigs[i];  sigs[i]=sigs[j];  sigs[j]=t
        t=ssids[i]; ssids[i]=ssids[j]; ssids[j]=t
        t=secs[i];  secs[i]=secs[j];  secs[j]=t
      }
  for (i = 0; i < n; i++)
    printf "  %s (%d%%, %s)\n", ssids[i], sigs[i], secs[i]
}')

show_active_ssid="${active_ssid:-n/a}"
show_ip4="${ip4:-n/a}"
show_ext_ip="${ext_ip:-n/a}"
show_gateway="${gateway:-n/a}"
show_dns="${dns:-n/a}"
show_dns_display="$show_dns"
show_band_chan="n/a"
[ -n "$band" ] && [ -n "$chan" ] && show_band_chan="$band ch$chan"
show_signal_rate="n/a"
[ -n "$signal" ] && [ -n "$rate" ] && show_signal_rate="${signal}% @ $rate"
show_latency="n/a"
[ -n "$lan_rtt" ] && [ -n "$wan_rtt" ] && show_latency="LAN $lan_rtt | WAN $wan_rtt"

masked_active_ssid="$show_active_ssid"
masked_ip4="$show_ip4"
masked_ext_ip="$show_ext_ip"
masked_gateway="$show_gateway"
masked_dns="$show_dns"
[ "$masked_active_ssid" != "n/a" ] && masked_active_ssid="<hidden>"
[ "$masked_ip4" != "n/a" ] && masked_ip4="<hidden>"
[ "$masked_ext_ip" != "n/a" ] && masked_ext_ip="<hidden>"
[ "$masked_gateway" != "n/a" ] && masked_gateway="<hidden>"
[ "$masked_dns" != "n/a" ] && masked_dns="<hidden>"

header_full="$(format_header_row "Interface:" "$iface")
$(format_header_row "Connected:" "$show_active_ssid")
$(format_header_row "IP (Int):" "$show_ip4")
$(format_header_row "IP (Ext):" "$show_ext_ip")
$(format_header_row "Gateway:" "$show_gateway")
$(format_header_row "DNS:" "$show_dns_display")
$(format_header_row "Band/Chan:" "$show_band_chan")
$(format_header_row "Signal/Rate:" "$show_signal_rate")
$(format_header_row "VPN:" "$vpn_status")
$(format_header_row "Latency:" "$show_latency")"

header_full_masked="$(format_header_row "Interface:" "$iface")
$(format_header_row "Connected:" "$masked_active_ssid")
$(format_header_row "IP (Int):" "$masked_ip4")
$(format_header_row "IP (Ext):" "$masked_ext_ip")
$(format_header_row "Gateway:" "$masked_gateway")
$(format_header_row "DNS:" "$masked_dns")
$(format_header_row "Band/Chan:" "$show_band_chan")
$(format_header_row "Signal/Rate:" "$show_signal_rate")
$(format_header_row "VPN:" "$vpn_status")
$(format_header_row "Latency:" "$show_latency")"

# Compact mode shows core connectivity lines only; full mode shows full diagnostics.
header_compact_clear="$(format_header_row "Interface:" "$iface")
$(format_header_row "Connected:" "$show_active_ssid")
$(format_header_row "IP (Int):" "$show_ip4")
$(format_header_row "IP (Ext):" "$show_ext_ip")"

header_compact_masked="$(format_header_row "Interface:" "$iface")
$(format_header_row "Connected:" "$masked_active_ssid")
$(format_header_row "IP (Int):" "$masked_ip4")
$(format_header_row "IP (Ext):" "$masked_ext_ip")"

show_wifi_popup "$header_compact_masked" "$header_full_masked" "$header_compact_clear" "$header_full" "$list"
