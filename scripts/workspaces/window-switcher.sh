#!/usr/bin/env bash
# Compositor-aware open window list and switcher using Rofi with dynamic icon resolution.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

# shellcheck source=waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=xdg-icons-lib.sh
# Desktop-file icon maps + guess_icon (shared with kde-notifications-rofi).
. "$WAYBAR_SCRIPTS/lib/xdg-icons-lib.sh"

session="$(detect_compositor)"
tab=$'\t'

# Optional output from active-window on-click / WAYBAR_OUTPUT_NAME.
out_name="${1:-${WAYBAR_OUTPUT_NAME:-}}"
if [ -n "$out_name" ]; then
  export WAYBAR_OUTPUT_NAME="$out_name"
fi

filter_output=0
_wspo=$(waybar_settings_get '.window_switcher.per_output' 'true')
case "$_wspo" in false | False | FALSE | 0 | no | No | NO | off | Off | OFF) ;; *)
  [ -n "${WAYBAR_OUTPUT_NAME:-}" ] && filter_output=1
  ;;
esac

switcher_theme=$(waybar_settings_get '.rofi.switcher.width' '') # Theme file is retrieved in the execution block if needed, but we check width here
switcher_theme_file=$(waybar_settings_get '.rofi.theme' '')
switcher_theme_file="${switcher_theme_file/\$WAYBAR_HOME/$WAYBAR_HOME}"
switcher_theme_file="${switcher_theme_file/\$\{WAYBAR_HOME\}/$WAYBAR_HOME}"
switcher_width=$(waybar_settings_get '.rofi.switcher.width' '650')

# Theme colors from settings (keep switcher layout; only swap palette).
sw_critical=$(waybar_settings_get '.theme.colors.critical' '#ff2a7f')
sw_accent=$(waybar_settings_get '.theme.colors.accent' '#00e5ff')
sw_ws_visible=$(waybar_settings_get '.theme.colors.workspace_visible' '')
if [[ "$sw_accent" == rgba* ]] && [[ -n "$sw_ws_visible" && "$sw_ws_visible" != "null" ]]; then
  sw_accent="$sw_ws_visible"
elif [[ -z "$sw_accent" || "$sw_accent" == "null" ]]; then
  sw_accent="${sw_ws_visible:-#00e5ff}"
fi
sw_fg=$(waybar_settings_get '.theme.colors.foreground' '#c8f6ff')
sw_bg=$(waybar_settings_get '.theme.colors.background' 'rgba(6, 7, 14, 0.94)')
sw_warning=$(waybar_settings_get '.theme.colors.warning' '#ffe600')

# Soft rgba companions from hex (best-effort; fall back to cyberpunk defaults).
_hex_rgb() {
  local h="${1#\#}"
  if [[ ${#h} -eq 6 ]]; then
    printf '%d, %d, %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
  else
    printf ''
  fi
}
_rgba() {
  local c="$1" a="$2" fb="$3" rgb
  rgb="$(_hex_rgb "$c")"
  if [[ -n "$rgb" ]]; then
    printf 'rgba(%s, %s)' "$rgb" "$a"
  else
    printf '%s' "$fb"
  fi
}
sw_accent_bg08="$(_rgba "$sw_accent" "0.08" "rgba(0, 229, 255, 0.08)")"
sw_accent_bd35="$(_rgba "$sw_accent" "0.35" "rgba(0, 229, 255, 0.35)")"
sw_accent_bd15="$(_rgba "$sw_accent" "0.15" "rgba(0, 229, 255, 0.15)")"
sw_accent_bg04="$(_rgba "$sw_accent" "0.04" "rgba(0, 229, 255, 0.04)")"
sw_crit_bg18="$(_rgba "$sw_critical" "0.18" "rgba(255, 42, 127, 0.18)")"
sw_crit_fg65="$(_rgba "$sw_critical" "0.65" "rgba(255, 42, 127, 0.65)")"
sw_fg65="$(_rgba "$sw_fg" "0.65" "rgba(200, 246, 255, 0.65)")"

theme="
  window {
    width: ${switcher_width}px;
    location: center;
    anchor: center;
    border: 2px;
    border-color: ${sw_accent};
    border-radius: 8px;
    background-color: ${sw_bg};
    padding: 15px;
  }
  mainbox {
    spacing: 12px;
    children: [ inputbar, listview ];
    background-color: transparent;
  }
  inputbar {
    background-color: ${sw_accent_bg08};
    border: 1px;
    border-color: ${sw_accent_bd35};
    border-radius: 6px;
    padding: 8px 12px;
    text-color: ${sw_fg};
    children: [ prompt, entry ];
  }
  prompt {
    text-color: ${sw_critical};
    margin: 0px 8px 0px 0px;
    background-color: transparent;
  }
  entry {
    text-color: ${sw_fg};
    background-color: transparent;
  }
  listview {
    lines: 8;
    columns: 1;
    fixed-height: false;
    background-color: transparent;
    spacing: 6px;
  }
  element {
    padding: 8px 12px;
    border: 1px;
    border-color: ${sw_accent_bd15};
    border-radius: 6px;
    background-color: ${sw_accent_bg04};
    spacing: 12px;
  }
  element normal.normal {
    background-color: ${sw_accent_bg04};
    border-color: ${sw_accent_bd15};
    text-color: ${sw_fg65};
  }
  element normal.urgent {
    background-color: ${sw_accent_bg04};
    border-color: ${sw_accent_bd15};
    text-color: ${sw_crit_fg65};
  }
  element normal.active {
    background-color: ${sw_accent_bg04};
    border-color: ${sw_accent_bd15};
    text-color: ${sw_accent};
  }
  element alternate.normal {
    background-color: ${sw_accent_bg04};
    border-color: ${sw_accent_bd15};
    text-color: ${sw_fg65};
  }
  element alternate.urgent {
    background-color: ${sw_accent_bg04};
    border-color: ${sw_accent_bd15};
    text-color: ${sw_crit_fg65};
  }
  element alternate.active {
    background-color: ${sw_accent_bg04};
    border-color: ${sw_accent_bd15};
    text-color: ${sw_accent};
  }
  element selected.normal {
    background-color: ${sw_crit_bg18};
    border: 1px;
    border-color: ${sw_critical};
    text-color: ${sw_critical};
  }
  element selected.urgent {
    background-color: ${sw_crit_bg18};
    border: 1px;
    border-color: ${sw_critical};
    text-color: ${sw_warning};
  }
  element selected.active {
    background-color: ${sw_crit_bg18};
    border: 1px;
    border-color: ${sw_critical};
    text-color: ${sw_critical};
  }
  element-icon {
    size: 24px;
    background-color: transparent;
  }
  element-text {
    font: \"JetBrainsMono Nerd Font 11\";
    background-color: transparent;
    text-color: inherit;
    vertical-align: 0.5;
  }
"

# Desktop icon maps (shared lib)
xdg_icons_load_maps "${XDG_CACHE_HOME:-$HOME/.cache}/window-switcher-icons.cache"

if [ "$session" = "hyprland" ]; then
  if ! command -v hyprctl >/dev/null 2>&1; then
    exit 1
  fi
  clients="$(hyprctl clients -j)"
  if [ "$filter_output" -eq 1 ]; then
    mid=$(hyprctl monitors -j 2>/dev/null | jq -r --arg n "$WAYBAR_OUTPUT_NAME" '.[] | select(.name == $n) | .id' | head -n1 || true)
    if [ -n "$mid" ]; then
      clients="$(printf '%s' "$clients" | jq --argjson mid "$mid" '[.[] | select(.monitor == $mid)]')"
    fi
  fi
  count="$(echo "$clients" | jq 'length')"
  if [ "$count" -eq 0 ]; then
    notify-send "Window Switcher" "No open windows found"
    exit 0
  fi

  # Format: "address<tab>class<tab>title (workspace)"
  mapfile -t client_data < <(echo "$clients" | jq -r --arg t "$tab" '.[] | "\(.address)\($t)\(.class)\($t)[\(.class)] \(.title) (WS: \(.workspace.name))"')

  if [ "${#client_data[@]}" -eq 0 ]; then
    exit 0
  fi

  declare -a ids=()
  declare -a displays=()
  declare -a icons=()

  for line in "${client_data[@]}"; do
    addr="${line%%"$tab"*}"
    rest="${line#*"$tab"}"
    class="${rest%%"$tab"*}"
    disp="${rest#*"$tab"}"

    # Lookup icon using our dynamic guesser (class acts as the app name hint)
    icon_name="$(guess_icon "$disp" "$class")"

    ids+=("$addr")
    displays+=("$disp")
    icons+=("$icon_name")
  done

  rofi_args=(-dmenu -i -p "Switch to:" -show-icons)
  [ -n "$switcher_theme_file" ] && [ -f "$switcher_theme_file" ] && rofi_args+=(-theme "$switcher_theme_file")
  rofi_args+=(-theme-str "$theme")

  selected=$(for i in "${!displays[@]}"; do
    printf "%s\0icon\x1f%s\n" "${displays[i]}" "${icons[i]}"
  done | rofi "${rofi_args[@]}")

  if [ -n "$selected" ]; then
    for i in "${!displays[@]}"; do
      if [ "${displays[i]}" = "$selected" ]; then
        hyprctl dispatch focuswindow "address:${ids[i]}"
        exit 0
      fi
    done
  fi

elif [ "$session" = "kde" ]; then
  if ! command -v qdbus6 >/dev/null 2>&1; then
    exit 1
  fi
  # KDE runner query:
  # KWin exposes a KRunner search matching service under /WindowsRunner.
  # We query the "windows" search target to get a list of all active windows.
  # --literal prints raw DBus structures (lists of arrays containing properties).
  raw="$(timeout 2 qdbus6 --literal org.kde.KWin /WindowsRunner org.kde.krunner1.Match windows 2>/dev/null || true)"

  # Parse entries: ID | Title | AppName
  # We split the raw return string into individual window lines and extract fields natively via sed.
  mapfile -t parsed < <(printf "%s\n" "$raw" \
    | sed -E 's/\[Argument: \(sssida\{sv\}\) /\n/g' \
    | sed -n -E 's/^"(0_\{[^"]+\})",[[:space:]]*"([^"]*)",[[:space:]]*"([^"]*)",[[:space:]]*100,[[:space:]]*1.*/\1\t\2\t\3/p')

  declare -a ids=()
  declare -a displays=()
  declare -a icons=()

  for line in "${parsed[@]}"; do
    id="${line%%"$tab"*}"
    rest="${line#*"$tab"}"
    title="${rest%%"$tab"*}"
    app="${rest#*"$tab"}"

    # Filter out empty title and empty app
    if [ -z "$title" ] && [ -z "$app" ]; then
      continue
    fi

    if [ -z "$title" ]; then
      title="$app"
    fi

    if [ -n "$app" ] && [ "$app" != "null" ]; then
      display_name="[$app] $title"
    else
      display_name="$title"
    fi

    icon_name="$(guess_icon "$title" "$app")"

    ids+=("$id")
    displays+=("$display_name")
    icons+=("$icon_name")
  done

  if [ "${#displays[@]}" -eq 0 ]; then
    notify-send "Window Switcher" "No open windows found"
    exit 0
  fi

  rofi_args=(-dmenu -i -p "Switch to:" -show-icons)
  [ -n "$switcher_theme_file" ] && [ -f "$switcher_theme_file" ] && rofi_args+=(-theme "$switcher_theme_file")
  rofi_args+=(-theme-str "$theme")

  selected=$(for i in "${!displays[@]}"; do
    printf "%s\0icon\x1f%s\n" "${displays[i]}" "${icons[i]}"
  done | rofi "${rofi_args[@]}")

  if [ -n "$selected" ]; then
    for i in "${!displays[@]}"; do
      if [ "${displays[i]}" = "$selected" ]; then
        # Activating the selected window:
        # KRunner's Run interface focuses and switches desktop viewport to the matched window ID.
        timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "${ids[i]}" "" >/dev/null 2>&1 || true
        exit 0
      fi
    done
  fi
fi
