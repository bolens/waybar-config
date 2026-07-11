#!/usr/bin/env sh
# Shared helpers for side-info Waybar modules.

# normalize_token: Normalize token for display
normalize_token() {
  token="$1"
  printf '%s' "$token"
}

# item_text_or_dash: Show item text or dash if empty
item_text_or_dash() {
  text="$1"
  [ -n "$text" ] && printf '%s' "$text" || printf '-'
}

# portainer_tooltip: Stub for portainer_tooltip
portainer_tooltip() {
  printf 'Portainer status unavailable'
}
# format_duration_short: Format seconds as short duration string
format_duration_short() {
  raw="$1"
  case "$raw" in
    '' | *[!0-9]*)
      printf '%s' "$raw"
      return
      ;;
  esac
  if [ "$raw" -lt 60 ]; then
    printf '%ss' "$raw"
    return
  fi
  if [ "$raw" -lt 3600 ]; then
    printf '%sm' $((raw / 60))
    return
  fi
  if [ "$raw" -lt 86400 ]; then
    printf '%sh %sm' $((raw / 3600)) $(((raw % 3600) / 60))
    return
  fi
  printf '%sd %sh' $((raw / 86400)) $(((raw % 86400) / 3600))
}
# emit_line: Emit JSON for Waybar custom module
emit_line() {
  text="$1"
  tooltip="$2"
  class="$3"
  jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" '{text:$text, tooltip:$tooltip, class:$class}'
}
# format_lr_colored_label: Format label and value with color for active/inactive
format_lr_colored_label() {
  label="$1"
  value="$2"
  active="$3"
  color="#00e5ff"
  [ "$active" = "1" ] && color="#2cffb0"
  formatted="$(format_lr "$label" "$value")"
  printf '<span foreground="%s">%s</span>' "$color" "$formatted"
}
# list_preview_csv: Preview CSV lines up to a limit
list_preview_csv() {
  data="$1"
  limit="${2:-3}"
  cleaned="$(printf '%s\n' "$data" | awk 'NF')"
  [ -n "$cleaned" ] || {
    printf 'none'
    return
  }
  total="$(printf '%s\n' "$cleaned" | awk 'END {print NR + 0}')"
  shown="$(printf '%s\n' "$cleaned" | awk -v limit="$limit" 'NR>limit {exit} NR==1 {out=$0; next} {out=out", "$0} END {print out}')"
  if [ "$total" -gt "$limit" ] 2>/dev/null; then
    printf '%s (+%s more)' "$shown" "$((total - limit))"
    return
  fi
  printf '%s' "$shown"
}
# csv_add: Add an item to a CSV string
csv_add() {
  current="$1"
  item="$2"
  if [ -z "$current" ]; then
    printf '%s' "$item"
    return
  fi
  printf '%s, %s' "$current" "$item"
}
# preview_update_lines: Extract preview lines for a given source from tooltip text
preview_update_lines() {
  source="$1"
  tooltip="$2"
  limit="${3:-30}"
  # Extract lines for the given source from the tooltip
  # This is a fallback stub; real implementation should parse actual update lines if available
  printf 'Preview unavailable'
}
#!/usr/bin/env sh
# side-info-helpers.sh: Helper functions for side-info-status.sh

fit_text() {
  # Trim leading and trailing whitespace using POSIX shell expansion patterns
  local val="${1#${1%%[![:space:]]*}}"
  val="${val%${val##*[![:space:]]}}"
  printf '%s' "$val"
}

format_lr() {
  local label="$1"
  local value="$2"
  local label_len="${#label}"
  local value_len="${#value}"
  local line_width=24
  local max_label=$((line_width - value_len - 1))
  if [ "$max_label" -lt 1 ]; then
    max_label=1
  fi
  if [ "$label_len" -gt "$max_label" ]; then
    label="$(printf '%s' "$label" | cut -c1-"$max_label")"
    label_len="${#label}"
  fi
  local spaces=$((line_width - label_len - value_len))
  if [ "$spaces" -lt 1 ]; then
    spaces=1
  fi
  printf "%s%${spaces}s%s" "$label" "" "$value"
}

short_value() {
  value="$1"
  max_len="${2:-14}"
  len="${#value}"
  if [ "$len" -le "$max_len" ] 2>/dev/null; then
    printf '%s' "$value"
    return
  fi
  printf '%s' "$value" | cut -c1-"$max_len"
}

# Add more helpers as needed

bar_json_from_system_summary() {
  summary="$1"
  printf '%s' "$summary" | jq -c '
    if (.text? // "") != "" then .
    else
      (.line2 // "") as $cpu_line |
      ($cpu_line | split(" ") | map(select(length > 0)) | last // "?") as $cpu |
      ($cpu | rtrimstr("%") | tonumber? // 0) as $pct |
      {
        text: "󰍛 \($cpu)",
        tooltip: (
          [.tooltip, .tooltip1, .tooltip2, .tooltip3, .tooltip4, .tooltip5]
          | map(select(. != null and . != ""))
          | unique
          | join("\n")
        ),
        class: (
          if $pct >= 85 then "critical"
          elif $pct >= 60 then "warning"
          else (.class // "normal")
          end
        )
      }
    end
  '
}

bar_json_from_network_summary() {
  summary="$1"
  printf '%s' "$summary" | jq -c '
    if (.text? // "") != "" then .
    else
      (.line3 // "") as $ip_line |
      ($ip_line | split(" ") | map(select(length > 0)) | last // "-") as $ip |
      (.line2 // "") as $dev_line |
      ($dev_line | split(" ") | map(select(length > 0)) | last // "-") as $dev |
      (.line5 // "") as $ssid_line |
      ($ssid_line | split(" ") | map(select(length > 0)) | last // "-") as $ssid |
      {
        text: (
          if $ssid != "-" and $ssid != "n/a" then "󰤨 \($ssid)"
          elif $ip != "-" and $ip != "n/a" then "󰖩 \($ip)"
          else "󰖩 \($dev)"
          end
        ),
        tooltip: (
          [.tooltip, .tooltip1, .tooltip2, .tooltip3, .tooltip4, .tooltip5, .tooltip6]
          | map(select(. != null and . != ""))
          | unique
          | join("\n")
        ),
        class: (.class // "normal")
      }
    end
  '
}

# running_summary_tooltip: Stub for docker_summary
running_summary_tooltip() {
  lines="$1"
  running="$2"
  total="$3"
  printf 'Running containers: %s/%s' "$running" "$total"
}
