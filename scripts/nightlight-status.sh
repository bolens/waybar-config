#!/usr/bin/env bash
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
force_state_file="$cache_dir/nightlight-kde-force"
cache_file="$cache_dir/nightlight-status.json"
lock_dir="$cache_dir/nightlight-status.lock.d"
ttl="$(waybar_module_interval nightlight 60)"
stale_lock_ttl=90

mkdir -p "$cache_dir"


# shellcheck source=compositor-session.sh
. "${0%/*}/compositor-session.sh"
. "${0%/*}/waybar-settings.sh"

temp_setting=$(waybar_settings_get '.nightlight.temperature' '')

get_backend() {
  comp="$(detect_compositor)"
  if [ "$comp" = "kde" ]; then
    printf 'kde\n'
  else
    printf 'hypr\n'
  fi
}

qdbus_cmd() {
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 "$@"
  else
    qdbus "$@"
  fi
}

emit_inactive() {
  backend_name="$1"
  tooltip=$(printf 'Night light inactive\nBackend: %s\n\nLeft: toggle · Middle: force preview · Right: settings' "$backend_name")
  jq -cn \
    --arg text "󰌶 off" \
    --arg tooltip "$tooltip" \
    --arg class "inactive" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

emit_active() {
  temp_value="$1"
  backend_name="$2"
  extra="${3:-}"
  tooltip=$(printf 'Night light active\nTemperature: %sK\nBackend: %s%s\n\nLeft: toggle · Middle: force preview · Right: settings' \
    "$temp_value" "$backend_name" "$extra")
  jq -cn \
    --arg text "󰌵 ${temp_value}K" \
    --arg tooltip "$tooltip" \
    --arg class "active" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

emit_forced() {
  temp_value="$1"
  backend_name="$2"
  tooltip=$(printf 'Night light forced on\nTemperature: %sK\nBackend: %s\nMode: forced preview\n\nLeft: toggle · Middle: force preview · Right: settings' \
    "$temp_value" "$backend_name")
  jq -cn \
    --arg text "󰌵 ${temp_value}K" \
    --arg tooltip "$tooltip" \
    --arg class "forced" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

collect_json() {
  backend=$(get_backend)

  case "$backend" in
    kde)
      # KDE KWin Night Light Query:
      # We fetch enabled (boolean), inhibited (boolean), and currentTemperature (unsigned) properties
      # from the org.kde.KWin.NightLight interface.
      # busctl returns values with type descriptors like "b true" or "u 4500".
      # The awk script strips the type prefixes ("b " / "u ") and prints values space-separated.
      read -r enabled inhibited temp <<EOF
$(timeout 2 busctl --user get-property org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight enabled inhibited currentTemperature 2>/dev/null | awk '{
        gsub(/^[bu] /, "")
        printf "%s ", $0
      }
      END { print "" }')
EOF
      enabled="${enabled:-false}"
      inhibited="${inhibited:-false}"
      temp="${temp:-6500}"
      forced="false"

      if [ -f "$force_state_file" ]; then
        forced="true"
      fi

      if [ "$forced" = "true" ]; then
        emit_forced "$temp" "kde"
        return 0
      fi

      if [ "$enabled" = "true" ] && [ "$inhibited" != "true" ] && [ "$temp" -lt 6490 ] 2>/dev/null; then
        emit_active "$temp" "kde"
        return 0
      fi

      emit_inactive "kde"
      ;;
    *)
      if pgrep -x hyprsunset >/dev/null 2>&1; then
        cmdline=$(pgrep -af '^hyprsunset' | awk 'NR==1 {print; exit}' || true)
        temp=$(printf '%s\n' "$cmdline" | sed -n 's/.* -t \([0-9][0-9]*\).*/\1/p')
        [ -n "$temp" ] || temp="${temp_setting:-${HYPRSUNSET_TEMP:-4200}}"
        emit_active "$temp" "hyprsunset"
        return 0
      fi

      emit_inactive "hyprsunset"
      ;;
  esac
}

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  jq -cn \
    --arg text "󰖨" \
    --arg tooltip "Refreshing Night Light status in background" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

json="$(collect_json)"
printf '%s\n' "$json"

tmp="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp"
mv -f "$tmp" "$cache_file"
