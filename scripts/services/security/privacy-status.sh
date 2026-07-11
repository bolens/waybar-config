#!/usr/bin/env bash
# Always-visible privacy indicators with idle/in-use states.
set -euo pipefail

kind="${1:-}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/privacy-status.json"

icons() {
  case "$1" in
    screenshare) printf '%s' "󰍹" ;;
    webcam) printf '%s' "󰄀" ;;
    audio-in) printf '%s' "󰍬" ;;
    audio-out) printf '%s' "󰓃" ;;
    location) printf '%s' "󰋽" ;;
    *) return 1 ;;
  esac
}

labels() {
  case "$1" in
    screenshare) printf '%s' "Screen share" ;;
    webcam) printf '%s' "Webcam" ;;
    audio-in) printf '%s' "Microphone" ;;
    audio-out) printf '%s' "Audio output" ;;
    location) printf '%s' "Location" ;;
    *) return 1 ;;
  esac
}

# GeoClue2 DBus query:
# GeoClue2 manages location services on Linux. The script queries the GeoClue2 DBus interface
# to see if the location system is currently in use. If active, it iterates over all GeoClue
# client DBus paths to identify active clients and extract their Desktop IDs (App Names) to
# display in the tooltip.
collect_privacy_json() {
  local location_in_use="false"
  local location_apps=""
  if command -v busctl >/dev/null 2>&1; then
    local in_use
    # Query GeoClue Manager to verify if location service is actively accessed
    in_use=$(timeout 2 busctl get-property org.freedesktop.GeoClue2 /org/freedesktop/GeoClue2/Manager org.freedesktop.GeoClue2.Manager InUse 2>/dev/null || echo "b false")
    if [ "$in_use" = "b true" ]; then
      location_in_use="true"
      local client_paths
      # List client objects registered with GeoClue2 and search active ones
      client_paths=$(timeout 2 busctl tree org.freedesktop.GeoClue2 2>/dev/null | grep -o '/org/freedesktop/GeoClue2/Client/[0-9]\+' || true)
      local apps=()
      for path in $client_paths; do
        local active
        active=$(timeout 2 busctl get-property org.freedesktop.GeoClue2 "$path" org.freedesktop.GeoClue2.Client Active 2>/dev/null || echo "b false")
        if [ "$active" = "b true" ]; then
          local app_id
          app_id=$(timeout 2 busctl get-property org.freedesktop.GeoClue2 "$path" org.freedesktop.GeoClue2.Client DesktopId 2>/dev/null | cut -d' ' -f2- | tr -d '"' || true)
          if [ -n "$app_id" ]; then
            apps+=("$app_id")
          fi
        fi
      done
      if [ ${#apps[@]} -gt 0 ]; then
        location_apps=$(printf "%s, " "${apps[@]}" | sed 's/, $//')
      fi
    fi
  fi

  command -v pw-dump >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || {
    jq -cn \
      --arg loc_in "$location_in_use" \
      --arg loc_apps "$location_apps" \
      '{
        screenshare: {text:"󰍹",tooltip:"Screen share idle",class:"idle"},
        webcam: {text:"󰄀",tooltip:"Webcam idle",class:"idle"},
        "audio-in": {text:"󰍬",tooltip:"Microphone idle",class:"idle"},
        "audio-out": {text:"󰓃",tooltip:"Audio output idle",class:"idle"},
        location: {
          text: "󰋽",
          tooltip: (if ($loc_in == "true") then (if ($loc_apps != "") then "Location in use: " + $loc_apps else "Location in use" end) else "Location idle" end),
          class: (if ($loc_in == "true") then "in-use" else "idle" end)
        }
      }'
    return 0
  }

  # PipeWire Graph Query:
  # We query active multimedia nodes from PipeWire using pw-dump.
  # We distinguish webcam from screenshare by matching node descriptions / application hints
  # against keywords like "camera" or "webcam". "cava" (audio visualizer) is excluded from
  # microphone listings since it is an ambient observer.
  timeout 2 pw-dump 2>/dev/null | jq -c \
    --arg loc_in "$location_in_use" \
    --arg loc_apps "$location_apps" \
    '
    def app_name:
      .info.props["application.name"]
      // .info.props["media.name"]
      // .info.props["node.name"]
      // "unknown";
    def stream_node($class):
      select(.type == "PipeWire:Interface:Node")
      | select(.info.props["media.class"] == $class)
      | select(.info.state == "running")
      | select((.info.props["node.monitor"] // false) | not);
    def video_hint:
      [
        (.info.props["media.name"] // ""),
        (.info.props["application.name"] // ""),
        (.info.props["node.name"] // ""),
        (.info.props["pipewire.access.portal"] // ""),
        (.info.props["portal.access"] // "")
      ] | join("|");
    def is_webcam:
      video_hint | test("camera|webcam|v4l2|libcamera|kamera"; "i");
    [ .[] | stream_node("Stream/Input/Video") | select(is_webcam) | app_name ] as $webcam
    | [ .[] | stream_node("Stream/Input/Video") | select(is_webcam | not) | app_name ] as $screenshare
    | [ .[] | stream_node("Stream/Input/Audio") | app_name | select(. != "cava") ] as $audio_in
    | [ .[] | stream_node("Stream/Output/Audio") | app_name ] as $audio_out
    | {
        screenshare: {
          text: "󰍹",
          tooltip: (if ($screenshare | length > 0) then "Screen share in use: " + ($screenshare | join(", ")) else "Screen share idle" end),
          class: (if ($screenshare | length > 0) then "in-use" else "idle" end)
        },
        webcam: {
          text: "󰄀",
          tooltip: (if ($webcam | length > 0) then "Webcam in use: " + ($webcam | join(", ")) else "Webcam idle" end),
          class: (if ($webcam | length > 0) then "in-use" else "idle" end)
        },
        "audio-in": {
          text: "󰍬",
          tooltip: (if ($audio_in | length > 0) then "Microphone in use: " + ($audio_in | join(", ")) else "Microphone idle" end),
          class: (if ($audio_in | length > 0) then "in-use" else "idle" end)
        },
        "audio-out": {
          text: "󰓃",
          tooltip: (if ($audio_out | length > 0) then "Audio output in use: " + ($audio_out | join(", ")) else "Audio output idle" end),
          class: (if ($audio_out | length > 0) then "in-use" else "idle" end)
        },
        location: {
          text: "󰋽",
          tooltip: (if ($loc_in == "true") then (if ($loc_apps != "") then "Location in use: " + $loc_apps else "Location in use" end) else "Location idle" end),
          class: (if ($loc_in == "true") then "in-use" else "idle" end)
        }
      }
    '
}

emit_module_json() {
  local module_kind="$1"
  local target_file="$cache_dir/privacy-$module_kind.json"
  if [ -f "$target_file" ]; then
    cat "$target_file"
  else
    local icon label
    icon="$(icons "$module_kind")"
    label="$(labels "$module_kind")"
    printf '{"text":"%s","tooltip":"%s idle","class":"idle"}\n' "$icon" "$label"
  fi
}

case "$kind" in
  --refresh)
    json="$(collect_privacy_json)"
    printf '%s\n' "$json"

    # Split and write to individual files atomically
    printf '%s\n' "$json" | jq -c '.screenshare, .webcam, ."audio-in", ."audio-out", .location' | {
      read -r scr_line
      read -r cam_line
      read -r aud_in_line
      read -r aud_out_line
      read -r loc_line

      [ -n "$scr_line" ] && printf '%s\n' "$scr_line" >"$cache_dir/privacy-screenshare.json.tmp.$$" && mv -f "$cache_dir/privacy-screenshare.json.tmp.$$" "$cache_dir/privacy-screenshare.json"
      [ -n "$cam_line" ] && printf '%s\n' "$cam_line" >"$cache_dir/privacy-webcam.json.tmp.$$" && mv -f "$cache_dir/privacy-webcam.json.tmp.$$" "$cache_dir/privacy-webcam.json"
      [ -n "$aud_in_line" ] && printf '%s\n' "$aud_in_line" >"$cache_dir/privacy-audio-in.json.tmp.$$" && mv -f "$cache_dir/privacy-audio-in.json.tmp.$$" "$cache_dir/privacy-audio-in.json"
      [ -n "$aud_out_line" ] && printf '%s\n' "$aud_out_line" >"$cache_dir/privacy-audio-out.json.tmp.$$" && mv -f "$cache_dir/privacy-audio-out.json.tmp.$$" "$cache_dir/privacy-audio-out.json"
      [ -n "$loc_line" ] && printf '%s\n' "$loc_line" >"$cache_dir/privacy-location.json.tmp.$$" && mv -f "$cache_dir/privacy-location.json.tmp.$$" "$cache_dir/privacy-location.json"
    }
    ;;
  screenshare | webcam | audio-in | audio-out | location)
    mkdir -p "$cache_dir"
    if [ ! -f "$cache_dir/privacy-$kind.json" ]; then
      json="$(collect_privacy_json)"
      printf '%s\n' "$json" | jq -c '.screenshare, .webcam, ."audio-in", ."audio-out", .location' | {
        read -r scr_line
        read -r cam_line
        read -r aud_in_line
        read -r aud_out_line
        read -r loc_line

        # Write to files atomically via temporary files
        [ -n "$scr_line" ] && printf '%s\n' "$scr_line" >"$cache_dir/privacy-screenshare.json.tmp.$$" && mv -f "$cache_dir/privacy-screenshare.json.tmp.$$" "$cache_dir/privacy-screenshare.json"
        [ -n "$cam_line" ] && printf '%s\n' "$cam_line" >"$cache_dir/privacy-webcam.json.tmp.$$" && mv -f "$cache_dir/privacy-webcam.json.tmp.$$" "$cache_dir/privacy-webcam.json"
        [ -n "$aud_in_line" ] && printf '%s\n' "$aud_in_line" >"$cache_dir/privacy-audio-in.json.tmp.$$" && mv -f "$cache_dir/privacy-audio-in.json.tmp.$$" "$cache_dir/privacy-audio-in.json"
        [ -n "$aud_out_line" ] && printf '%s\n' "$aud_out_line" >"$cache_dir/privacy-audio-out.json.tmp.$$" && mv -f "$cache_dir/privacy-audio-out.json.tmp.$$" "$cache_dir/privacy-audio-out.json"
        [ -n "$loc_line" ] && printf '%s\n' "$loc_line" >"$cache_dir/privacy-location.json.tmp.$$" && mv -f "$cache_dir/privacy-location.json.tmp.$$" "$cache_dir/privacy-location.json"
      } 2>/dev/null || true
    fi
    emit_module_json "$kind"
    ;;
  *)
    printf 'Usage: %s screenshare|webcam|audio-in|audio-out|location|--refresh\n' "$0" >&2
    exit 1
    ;;
esac
