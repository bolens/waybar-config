#!/usr/bin/env sh
# side-info-network-summary.sh: Network summary logic for side-info-status.sh

network_summary() {
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-side-graphs/cache"
  mkdir -p "$cache_dir"
  if command -v read_cached_summary >/dev/null 2>&1; then
    cached="$(read_cached_summary "$cache_dir" network 2>/dev/null || true)"
    if [ -n "$cached" ]; then
      printf '%s\n' "$cached"
      return
    fi
  fi

  # Ensure format_lr / short_value exist when this file is sourced without network-tab.sh
  command -v short_value >/dev/null 2>&1 || . "$(dirname "$0")/side-info-helpers.sh"

  host_name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'host')"
  default_route="$(ip route show default 2>/dev/null | awk 'NR==1 {print; exit}' || true)"
  default_dev="$(printf '%s\n' "$default_route" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  gateway_ip="$(printf '%s\n' "$default_route" | awk '{print $3; exit}')"
  lan_ip=''
  if [ -n "$default_dev" ]; then
    lan_ip="$(ip -4 -o addr show dev "$default_dev" scope global 2>/dev/null | awk 'NR==1 {split($4, a, "/"); print a[1]; exit}' || true)"
  fi

  wifi_iface=''
  for path in /sys/class/net/*; do
    [ -d "$path/wireless" ] || continue
    wifi_iface="$(basename "$path")"
    break
  done

    wifi_ssid=''
    wifi_signal=''
    if [ -n "$wifi_iface" ] && command -v nmcli >/dev/null 2>&1; then
      wifi_ssid="$(timeout 2 nmcli -t -f GENERAL.CONNECTION dev show "$wifi_iface" 2>/dev/null | awk -F: 'NR==1 {print $2; exit}' || true)"
      [ "$wifi_ssid" = "--" ] && wifi_ssid=''
    fi
    if [ -z "$wifi_ssid" ] && command -v iwgetid >/dev/null 2>&1; then
      wifi_ssid="$(iwgetid -r 2>/dev/null || true)"
    fi
    if [ -n "$wifi_iface" ] && [ -r /proc/net/wireless ]; then
      wifi_signal="$(awk -v iface="$wifi_iface" '
        $1 ~ iface":" {
          gsub(/\./, "", $4)
          q = int($3)
          if (q > 70) q = 70
          if (q < 0) q = 0
          printf "%d%%", int((q / 70) * 100)
          exit
        }
      ' /proc/net/wireless 2>/dev/null || true)"
    fi

  ethernet_iface=''
  for path in /sys/class/net/*; do
    iface="$(basename "$path")"
    [ "$iface" = "lo" ] && continue
    [ -d "$path/wireless" ] && continue
    ethernet_iface="$iface"
    break
  done
  ethernet_state=''
  if [ -n "$ethernet_iface" ] && [ -f "/sys/class/net/$ethernet_iface/operstate" ]; then
    ethernet_state="$(cat "/sys/class/net/$ethernet_iface/operstate" 2>/dev/null || true)"
  fi

  ts_json="$(~/.config/waybar/scripts/tailscale-status.sh 2>/dev/null || true)"
  ts_tooltip=''
  ts_backend=''
  ts_ip=''
  ts_peers=''
  ts_exit=''
  if [ -n "$ts_json" ]; then
    ts_fields="$(printf '%s' "$ts_json" | jq -r '[.tooltip // "", .backend // "", .ipv4 // "", ((.online_peers // "") | tostring), .exit_node // ""] | @tsv')"
    tab=$(printf '\t')
    old_ifs=$IFS
    IFS=$tab
    set -- $ts_fields
    IFS=$old_ifs
    ts_tooltip="${1:-}"
    ts_backend="${2:-}"
    ts_ip="${3:-}"
    ts_peers="${4:-}"
    ts_exit="${5:-}"

    [ -n "$ts_backend" ] || ts_backend="$(printf '%s\n' "$ts_tooltip" | awk -F': ' '/^Backend:/ && !seen {print $2; seen=1}')"
    [ -n "$ts_ip" ] || ts_ip="$(printf '%s\n' "$ts_tooltip" | awk -F': ' '/^IPv4:/ && !seen {print $2; seen=1}')"
    [ -n "$ts_peers" ] || ts_peers="$(printf '%s\n' "$ts_tooltip" | awk -F': ' '/^Online peers:/ && !seen {print $2; seen=1}')"
    [ -n "$ts_exit" ] || ts_exit="$(printf '%s\n' "$ts_tooltip" | awk -F': ' '/^Exit node:/ && !seen {print $2; seen=1}')"
  fi

  bt_connected=''
  bt_tooltip='Bluetooth unavailable'
  if command -v bluetoothctl >/dev/null 2>&1; then
    bt_lines="$(timeout 3 bluetoothctl devices Connected 2>/dev/null || true)"
    bt_connected="$(printf '%s\n' "$bt_lines" | awk 'NF {count++} END {print count + 0}')"
    bt_names="$(printf '%s\n' "$bt_lines" | awk 'NF { $1=""; $2=""; sub(/^  */, ""); if ($0 != "") print }' || true)"
    bt_tooltip="Bluetooth connected devices: $(list_preview_csv "$bt_names" 4)"
    [ -n "$bt_connected" ] || bt_connected='0'
  fi

  summary="$(jq -cn \
    --arg line1 "$(format_lr "Host" "$(short_value "$host_name" 14)")" \
    --arg line2 "$(format_lr "Default dev" "$(item_text_or_dash "$default_dev")")" \
    --arg line3 "$(format_lr "LAN IPv4" "$(short_value "$(item_text_or_dash "$lan_ip")" 14)")" \
    --arg line4 "$(format_lr "Gateway" "$(short_value "$(item_text_or_dash "$gateway_ip")" 14)")" \
    --arg line5 "$(format_lr "WiFi SSID" "$(short_value "$(item_text_or_dash "$wifi_ssid")" 14)")" \
    --arg line6 "$(format_lr "WiFi signal" "$(item_text_or_dash "$wifi_signal")")" \
    --arg line7 "$(format_lr "Ethernet" "$(item_text_or_dash "$ethernet_state")")" \
    --arg line8 "$(format_lr "Tailnet" "$(item_text_or_dash "$ts_backend")")" \
    --arg line9 "$(format_lr "Tail peers" "$(item_text_or_dash "$ts_peers")")" \
    --arg line10 "$(format_lr "Bluetooth" "$(item_text_or_dash "$bt_connected")")" \
    --arg tooltip "Network overview" \
    --arg tooltip1 "Host: ${host_name}. Default route device: ${default_dev:-n/a}." \
    --arg tooltip2 "Default route: ${default_route:-unavailable}" \
    --arg tooltip3 "LAN IPv4 on ${default_dev:-default}: ${lan_ip:-n/a}. Tailscale IPv4: ${ts_ip:-n/a}." \
    --arg tooltip4 "Default gateway: ${gateway_ip:-n/a}." \
    --arg tooltip5 "WiFi interface: ${wifi_iface:-n/a}. SSID: ${wifi_ssid:-n/a}." \
    --arg tooltip6 "WiFi signal strength: ${wifi_signal:-n/a}." \
    --arg tooltip7 "Ethernet interface ${ethernet_iface:-n/a} state: ${ethernet_state:-n/a}." \
    --arg tooltip8 "$(item_text_or_dash "$ts_tooltip")" \
    --arg tooltip9 "Tailnet online peers: ${ts_peers:-n/a}. Exit node: ${ts_exit:-none}." \
    --arg tooltip10 "$bt_tooltip" \
    --arg class "normal" \
    '{line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, tooltip:$tooltip, tooltip1:$tooltip1, tooltip2:$tooltip2, tooltip3:$tooltip3, tooltip4:$tooltip4, tooltip5:$tooltip5, tooltip6:$tooltip6, tooltip7:$tooltip7, tooltip8:$tooltip8, tooltip9:$tooltip9, tooltip10:$tooltip10, class:$class}')"

  if command -v write_cached_summary >/dev/null 2>&1; then
    write_cached_summary "$cache_dir" network "$summary"
  fi

  printf '%s\n' "$summary"
}
