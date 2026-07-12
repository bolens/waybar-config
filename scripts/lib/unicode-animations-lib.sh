#!/usr/bin/env sh
# Shared library of Unicode animations for Waybar scripts.
# Sourced by modules to render high-fidelity loading spin frames.

get_anim_frame() {
  anim_name="$1"
  frame_index="$2"

  # Honor compositor/desktop reduced-motion when the helper is available.
  if [ -f "${WAYBAR_SCRIPTS:-}/lib/reduced-motion-lib.sh" ]; then
    # shellcheck disable=SC1091
    . "${WAYBAR_SCRIPTS}/lib/reduced-motion-lib.sh"
    if waybar_reduced_motion_active >/dev/null 2>&1; then
      # Static first frame (no spinner motion).
      frame_index=0
    fi
  fi

  case "$anim_name" in
    dots)
      # 10 frames
      set -- "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"
      idx=$((frame_index % 10))
      shift "$idx"
      printf '%s' "$1"
      ;;
    moon)
      # 8 frames
      set -- "🌑" "🌒" "🌓" "🌔" "🌕" "🌖" "🌗" "🌘"
      idx=$((frame_index % 8))
      shift "$idx"
      printf '%s' "$1"
      ;;
    clock)
      # 12 frames — \U escapes avoid editor/shell encoding breakage for clock faces.
      set -- "$(printf '\U0001f55b')" "$(printf '\U0001f550')" "$(printf '\U0001f551')" "$(printf '\U0001f552')" "$(printf '\U0001f553')" "$(printf '\U0001f554')" "$(printf '\U0001f555')" "$(printf '\U0001f556')" "$(printf '\U0001f557')" "$(printf '\U0001f558')" "$(printf '\U0001f559')" "$(printf '\U0001f55a')"
      idx=$((frame_index % 12))
      shift "$idx"
      printf '%s' "$1"
      ;;
    pulse)
      # 15 frames
      set -- " " "▂" "▃" "▄" "▅" "▆" "▇" "█" "▇" "▆" "▅" "▄" "▃" "▂" " "
      idx=$((frame_index % 15))
      shift "$idx"
      printf '%s' "$1"
      ;;
    bounce)
      # 4 frames
      set -- "▖" "▘" "▝" "▗"
      idx=$((frame_index % 4))
      shift "$idx"
      printf '%s' "$1"
      ;;
    arrows)
      # 8 frames
      set -- "←" "↖" "↑" "↗" "→" "↘" "↓" "↙"
      idx=$((frame_index % 8))
      shift "$idx"
      printf '%s' "$1"
      ;;
    *)
      printf ''
      ;;
  esac
}

animate_command() {
  anim_name="$1"
  label="$2"
  tooltip="$3"
  shift 3

  # Skip loops and animations if running in the background
  if [ "${WAYBAR_BACKGROUND:-0}" = "1" ]; then
    "$@"
    return $?
  fi

  if [ -f "${WAYBAR_SCRIPTS:-}/lib/reduced-motion-lib.sh" ]; then
    # shellcheck disable=SC1091
    . "${WAYBAR_SCRIPTS}/lib/reduced-motion-lib.sh"
    if waybar_reduced_motion_active >/dev/null 2>&1; then
      "$@"
      return $?
    fi
  fi

  # Unique files for concurrent modules
  tmp_out=$(mktemp)
  tmp_err=$(mktemp)

  # Start the command in the background
  "$@" >"$tmp_out" 2>"$tmp_err" &
  cmd_pid=$!

  # Animate until command finishes
  frame=0
  while kill -0 "$cmd_pid" 2>/dev/null; do
    spinner=$(get_anim_frame "$anim_name" "$frame")
    if command -v emit_waybar_json >/dev/null 2>&1; then
      emit_waybar_json "$spinner $label" "$tooltip" "loading"
    else
      clean_label=$(printf '%s' "$label" | sed 's/"/\\"/g')
      jq -cn \
        --arg text "$spinner $clean_label" \
        --arg tooltip "$tooltip" \
        --arg class "loading" \
        '{text:$text, tooltip:$tooltip, class:$class}'
    fi
    frame=$((frame + 1))
    sleep 0.1
  done

  # Read command output and exit status
  wait "$cmd_pid"
  cat "$tmp_out"
  rm -f "$tmp_out" "$tmp_err"
}
