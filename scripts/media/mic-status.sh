#!/usr/bin/env sh
# Microphone mute status for Waybar (PipeWire/wpctl; signal-driven).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
source_cache="$cache_dir/mic-source-label.txt"
status_cache="$cache_dir/mic-status.json"
lock_dir="$cache_dir/mic-status.lock.d"
source_cache_ttl=60
ttl="$(waybar_module_interval mic 60)"
stale_lock_ttl=90

mkdir -p "$cache_dir"

mixer=$(jq -r '.apps.audio_mixer // "audio mixer"' "$WAYBAR_HOME/data/waybar-settings.json" 2>/dev/null || printf 'audio mixer')
[ -n "$mixer" ] || mixer="audio mixer"
mixer_lc=$(printf '%s' "$mixer" | tr '[:upper:]' '[:lower:]')
case "$mixer_lc" in
  *goxlr*) mixer_label="GoXLR" ;;
  *)
    mixer_label=${mixer%% *}
    mixer_label=${mixer_label%-launcher}
    ;;
esac

collect_json() {
  v=$(timeout 2 wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)
  if [ -z "$v" ]; then
    printf '{"text":"󰍭 ?","class":"unknown","tooltip":"No default audio source"}\n'
    return 0
  fi

  default_source=$(timeout 2 pactl info 2>/dev/null | awk -F': ' '/^Default Source:/ {print $2; exit}') || true
  source_label="$default_source"
  if [ -n "$default_source" ]; then
    age=$(cache_file_age "$source_cache")
    if [ "$age" -lt "$source_cache_ttl" ] 2>/dev/null; then
      cached_line=$(grep -F "${default_source}|" "$source_cache" 2>/dev/null | head -n1 || true)
      if [ -n "$cached_line" ]; then
        source_label=$(printf '%s' "$cached_line" | awk -F'|' '{print $2}')
      fi
    fi

    if [ -z "${source_label:-}" ] || [ "$source_label" = "$default_source" ]; then
      source_desc=$(timeout 2 pactl list sources 2>/dev/null | awk -v target="$default_source" '
        BEGIN { in_block=0; name=""; desc=""; found=0 }
        /^Source #[0-9]+/ {
          if (in_block && name==target) {
            print desc
            found=1
            exit
          }
          in_block=1
          name=""
          desc=""
          next
        }
        in_block && /^[[:space:]]*Name:[[:space:]]*/ {
          sub(/^[[:space:]]*Name:[[:space:]]*/, "")
          name=$0
          next
        }
        in_block && /^[[:space:]]*Description:[[:space:]]*/ {
          sub(/^[[:space:]]*Description:[[:space:]]*/, "")
          desc=$0
          next
        }
        END {
          if (!found && in_block && name==target) {
            print desc
          }
        }
      ') || true
      [ -n "$source_desc" ] && source_label="$source_desc"
      if [ -n "$source_label" ]; then
        tmp="$source_cache.tmp.$$"
        {
          [ -f "$source_cache" ] && grep -v -F "${default_source}|" "$source_cache" 2>/dev/null || true
          printf '%s|%s\n' "$default_source" "$source_label"
        } >"$tmp"
        mv -f "$tmp" "$source_cache"
      fi
    fi
  fi
  [ -z "$source_label" ] && source_label="Unknown input"

  mic_users=$(timeout 2 pactl list source-outputs 2>/dev/null \
    | awk '/application\.name =/ { gsub(/.*application\.name = "/, ""); gsub(/".*/, ""); print }' \
    | sort -u | tr '\n' '\n')

  if printf '%s' "$v" | rg -Fq MUTED; then
    if [ -n "$mic_users" ]; then
      tooltip=$(printf 'Input: %s\nLevel: 0%%\nStatus: muted\nIn use by:\n%s\n\nLeft: %s · Right: audio menu · Middle: toggle mute' "$source_label" "$mic_users" "$mixer_label")
    else
      tooltip=$(printf 'Input: %s\nLevel: 0%%\nStatus: muted\n\nLeft: %s · Right: audio menu · Middle: toggle mute' "$source_label" "$mixer_label")
    fi
    printf '{"text":"󰍭","class":"muted","tooltip":"%s"}\n' "$(json_escape "$tooltip")"
    return 0
  fi

  pct=$(printf '%s' "$v" | awk '{printf "%d", $2*100}')
  if [ -n "$mic_users" ]; then
    tooltip=$(printf 'Input: %s\nLevel: %s%%\nStatus: live\nIn use by:\n%s\n\nLeft: %s · Right: audio menu · Middle: toggle mute' "$source_label" "$pct" "$mic_users" "$mixer_label")
  else
    tooltip=$(printf 'Input: %s\nLevel: %s%%\nStatus: live\n\nLeft: %s · Right: audio menu · Middle: toggle mute' "$source_label" "$pct" "$mixer_label")
  fi
  printf '{"text":"󰍬 %3d%%","class":"active","tooltip":"%s"}\n' "$pct" "$(json_escape "$tooltip")"
}

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$status_cache" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi

  emit_waybar_json "󰍬" "Refreshing Microphone status in background" "disabled"
  exit 0
fi

json="$(collect_json)"
printf '%s\n' "$json"

tmp="$status_cache.tmp.$$"
printf '%s\n' "$json" >"$tmp"
mv -f "$tmp" "$status_cache"
