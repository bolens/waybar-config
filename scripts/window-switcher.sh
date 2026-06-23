#!/usr/bin/env bash
# Compositor-aware open window list and switcher using Rofi with dynamic icon resolution.
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

# shellcheck source=waybar-cache-helpers.sh
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi

session="$(detect_compositor)"
tab=$'\t'

theme='
  window {
    width: 650px;
    location: center;
    anchor: center;
    border: 2px;
    border-color: #00e5ff;
    border-radius: 8px;
    background-color: rgba(6, 7, 14, 0.94);
    padding: 15px;
  }
  mainbox {
    spacing: 12px;
    children: [ inputbar, listview ];
    background-color: transparent;
  }
  inputbar {
    background-color: rgba(0, 229, 255, 0.08);
    border: 1px;
    border-color: rgba(0, 229, 255, 0.35);
    border-radius: 6px;
    padding: 8px 12px;
    text-color: #c8f6ff;
    children: [ prompt, entry ];
  }
  prompt {
    text-color: #ff2a7f;
    margin: 0px 8px 0px 0px;
    background-color: transparent;
  }
  entry {
    text-color: #c8f6ff;
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
    border-color: rgba(0, 229, 255, 0.15);
    border-radius: 6px;
    background-color: rgba(0, 229, 255, 0.04);
    spacing: 12px;
  }
  element normal.normal {
    background-color: rgba(0, 229, 255, 0.04);
    border-color: rgba(0, 229, 255, 0.15);
    text-color: rgba(200, 246, 255, 0.65);
  }
  element normal.urgent {
    background-color: rgba(0, 229, 255, 0.04);
    border-color: rgba(0, 229, 255, 0.15);
    text-color: rgba(255, 42, 127, 0.65);
  }
  element normal.active {
    background-color: rgba(0, 229, 255, 0.04);
    border-color: rgba(0, 229, 255, 0.15);
    text-color: #00e5ff;
  }
  element alternate.normal {
    background-color: rgba(0, 229, 255, 0.04);
    border-color: rgba(0, 229, 255, 0.15);
    text-color: rgba(200, 246, 255, 0.65);
  }
  element alternate.urgent {
    background-color: rgba(0, 229, 255, 0.04);
    border-color: rgba(0, 229, 255, 0.15);
    text-color: rgba(255, 42, 127, 0.65);
  }
  element alternate.active {
    background-color: rgba(0, 229, 255, 0.04);
    border-color: rgba(0, 229, 255, 0.15);
    text-color: #00e5ff;
  }
  element selected.normal {
    background-color: rgba(255, 42, 127, 0.18);
    border: 1px;
    border-color: #ff2a7f;
    text-color: #ff2a7f;
  }
  element selected.urgent {
    background-color: rgba(255, 42, 127, 0.18);
    border: 1px;
    border-color: #ff2a7f;
    text-color: #ffe600;
  }
  element selected.active {
    background-color: rgba(255, 42, 127, 0.18);
    border: 1px;
    border-color: #ff2a7f;
    text-color: #ff2a7f;
  }
  element-icon {
    size: 24px;
    background-color: transparent;
  }
  element-text {
    font: "JetBrainsMono Nerd Font 11";
    background-color: transparent;
    text-color: inherit;
    vertical-align: 0.5;
  }
'

# Dynamic desktop file mappings cache system
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_FILE="$CACHE_DIR/window-switcher-icons.cache"
mkdir -p "$CACHE_DIR"

declare -A class_to_icon
declare -A name_to_icon
declare -A exec_to_icon

rebuild_cache=false
if [ ! -s "$CACHE_FILE" ]; then
  rebuild_cache=true
else
  max_mtime=0
  for d in "/usr/share/applications" "$HOME/.local/share/applications" "/var/lib/flatpak/exports/share/applications" "$HOME/.local/share/flatpak/exports/share/applications"; do
    if [ -d "$d" ]; then
      mtime=$(stat -c %Y "$d" 2>/dev/null || echo 0)
      if [ "$mtime" -gt "$max_mtime" ]; then
        max_mtime="$mtime"
      fi
    fi
  done
  
  cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  if [ "$max_mtime" -gt "$cache_mtime" ]; then
    rebuild_cache=true
  fi
fi

if [ "$rebuild_cache" = true ]; then
  shopt -s nullglob
  files=(
    "/usr/share/applications"/*.desktop
    "$HOME/.local/share/applications"/*.desktop
    "/var/lib/flatpak/exports/share/applications"/*.desktop
    "$HOME/.local/share/flatpak/exports/share/applications"/*.desktop
  )
  shopt -u nullglob
  
  declare -A tmp_class=()
  declare -A tmp_name=()
  declare -A tmp_exec=()
  
  tab=$'\t'
  if [ "${#files[@]}" -gt 0 ]; then
    while IFS="$tab" read -r type key val; do
      case "$type" in
        class) tmp_class["$key"]="$val" ;;
        name) tmp_name["$key"]="$val" ;;
        exec) tmp_exec["$key"]="$val" ;;
      esac
    done < <(awk -F= '
      BEGINFILE {
        name=""; icon=""; wmclass=""; exec=""; in_entry=0;
      }
      /^\[Desktop Entry\]/ {
        in_entry=1;
        next;
      }
      /^\[/ {
        in_entry=0;
      }
      in_entry {
        sub(/\r$/, "");
        if ($1 == "Name" && name == "") {
          name=$2;
        } else if ($1 == "Icon" && icon == "") {
          icon=$2;
        } else if ($1 == "StartupWMClass" && wmclass == "") {
          wmclass=$2;
        } else if ($1 == "Exec" && exec == "") {
          split($2, parts, " ");
          exec=parts[1];
          sub(/.*\//, "", exec);
        }
      }
      ENDFILE {
        if (icon != "") {
          if (wmclass != "") print "class\t" tolower(wmclass) "\t" icon;
          if (name != "") print "name\t" tolower(name) "\t" icon;
          if (exec != "") print "exec\t" tolower(exec) "\t" icon;
          
          split(FILENAME, fn_parts, "/");
          fn = fn_parts[length(fn_parts)];
          sub(/\.desktop$/, "", fn);
          print "exec\t" tolower(fn) "\t" icon;
        }
      }
    ' "${files[@]}" 2>/dev/null || true)
  fi
  
  for k in "${!tmp_class[@]}"; do class_to_icon["$k"]="${tmp_class[$k]}"; done
  for k in "${!tmp_name[@]}"; do name_to_icon["$k"]="${tmp_name[$k]}"; done
  for k in "${!tmp_exec[@]}"; do exec_to_icon["$k"]="${tmp_exec[$k]}"; done
  
  tmp_cache="$CACHE_FILE.tmp.$$"
  declare -p class_to_icon name_to_icon exec_to_icon > "$tmp_cache" 2>/dev/null || true
  mv -f "$tmp_cache" "$CACHE_FILE" 2>/dev/null || true
  cleanup_stale_tmp_files "$CACHE_DIR"
else
  . "$CACHE_FILE"
fi

guess_icon() {
  local title="$1"
  local app="$2"
  
  local app_lower
  app_lower=$(echo "${app:-}" | tr 'A-Z' 'a-z')
  local title_lower
  title_lower=$(echo "${title:-}" | tr 'A-Z' 'a-z')
  
  # 1. Direct app name mapping
  if [ -n "$app_lower" ] && [ "$app_lower" != "null" ]; then
    if [ -n "${class_to_icon[$app_lower]:-}" ]; then
      printf '%s' "${class_to_icon[$app_lower]}"
      return
    elif [ -n "${exec_to_icon[$app_lower]:-}" ]; then
      printf '%s' "${exec_to_icon[$app_lower]}"
      return
    elif [ -n "${name_to_icon[$app_lower]:-}" ]; then
      printf '%s' "${name_to_icon[$app_lower]}"
      return
    fi
  fi
  
  # 2. Window title matches desktop name or class exactly
  if [ -n "${name_to_icon[$title_lower]:-}" ]; then
    printf '%s' "${name_to_icon[$title_lower]}"
    return
  fi
  if [ -n "${class_to_icon[$title_lower]:-}" ]; then
    printf '%s' "${class_to_icon[$title_lower]}"
    return
  fi
  
  # 3. Substring search in window title for matching names/classes
  for class_key in "${!class_to_icon[@]}"; do
    if [[ "$title_lower" == *"$class_key"* ]]; then
      printf '%s' "${class_to_icon[$class_key]}"
      return
    fi
  done
  for name_key in "${!name_to_icon[@]}"; do
    if [ "${#name_key}" -gt 2 ] && [[ "$title_lower" == *"$name_key"* ]]; then
      printf '%s' "${name_to_icon[$name_key]}"
      return
    fi
  done
  for exec_key in "${!exec_to_icon[@]}"; do
    if [ "${#exec_key}" -gt 2 ] && [[ "$title_lower" == *"$exec_key"* ]]; then
      printf '%s' "${exec_to_icon[$exec_key]}"
      return
    fi
  done
  
  # 4. Fallback for shell prompts & terminal processes (maps to default terminal emulator Ghostty)
  if [[ "$title" =~ ^[~/] || "$title_lower" == *"bash"* || "$title_lower" == *"sh"* || "$title_lower" == *"agy"* ]]; then
    if [ -n "${exec_to_icon["ghostty"]:-}" ]; then
      printf '%s' "${exec_to_icon["ghostty"]}"
      return
    fi
  fi
  
  # 5. Generic fallback
  if [ -n "$app_lower" ] && [ "$app_lower" != "null" ]; then
    printf '%s' "$app_lower"
  else
    printf 'applications-other'
  fi
}

if [ "$session" = "hyprland" ]; then
  if ! command -v hyprctl >/dev/null 2>&1; then
    exit 1
  fi
  clients="$(hyprctl clients -j)"
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
    addr="${line%%$tab*}"
    rest="${line#*$tab}"
    class="${rest%%$tab*}"
    disp="${rest#*$tab}"
    
    # Lookup icon using our dynamic guesser (class acts as the app name hint)
    icon_name="$(guess_icon "$disp" "$class")"
    
    ids+=( "$addr" )
    displays+=( "$disp" )
    icons+=( "$icon_name" )
  done

  selected=$(for i in "${!displays[@]}"; do
    printf "%s\0icon\x1f%s\n" "${displays[i]}" "${icons[i]}"
  done | rofi -dmenu -i -p "Switch to:" -show-icons -theme-str "$theme")
  
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
  mapfile -t parsed < <(printf "%s\n" "$raw" | \
    sed -E 's/\[Argument: \(sssida\{sv\}\) /\n/g' | \
    sed -n -E 's/^"(0_\{[^"]+\})",[[:space:]]*"([^"]*)",[[:space:]]*"([^"]*)",[[:space:]]*100,[[:space:]]*1.*/\1\t\2\t\3/p')
  
  declare -a ids=()
  declare -a displays=()
  declare -a icons=()

  for line in "${parsed[@]}"; do
    id="${line%%$tab*}"
    rest="${line#*$tab}"
    title="${rest%%$tab*}"
    app="${rest#*$tab}"
    
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
    
    ids+=( "$id" )
    displays+=( "$display_name" )
    icons+=( "$icon_name" )
  done

  if [ "${#displays[@]}" -eq 0 ]; then
    notify-send "Window Switcher" "No open windows found"
    exit 0
  fi

  selected=$(for i in "${!displays[@]}"; do
    printf "%s\0icon\x1f%s\n" "${displays[i]}" "${icons[i]}"
  done | rofi -dmenu -i -p "Switch to:" -show-icons -theme-str "$theme")
  
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
