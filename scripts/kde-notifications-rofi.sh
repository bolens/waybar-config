#!/usr/bin/env bash
# Premium themed Rofi notification center interface matching the App Switcher.
set -euo pipefail

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
history_file="$cache_dir/kde-notifications-history.json"

script_dir="$(dirname "$0")"
# shellcheck source=waybar-cache-helpers.sh
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi



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
    children: [ inputbar, message, listview ];
    background-color: transparent;
  }
  message {
    padding: 8px 12px;
    border: 1px;
    border-radius: 6px;
    border-color: rgba(0, 229, 255, 0.15);
    background-color: rgba(0, 229, 255, 0.04);
  }
  textbox {
    text-color: #c8f6ff;
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
    placeholder: "Search notifications...";
    placeholder-color: #7fa8b2;
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

empty_state=false
if [ ! -f "$history_file" ]; then
    empty_state=true
else
    notifs="$(cat "$history_file")"
    count="$(echo "$notifs" | jq 'length')"
    if [ "$count" -eq 0 ]; then
        empty_state=true
    fi
fi

if [ "$empty_state" = true ]; then
    printf "No notification history.\0icon\x1fnotifications-disabled-symbolic\n" | \
        rofi -dmenu -i -p "Notifications:" -show-icons -theme-str "$theme" 2>/dev/null || true
    exit 0
fi

# Dynamic desktop file mappings cache system
# Dynamic Desktop Icon Mapping Cache System:
# Reading all desktop entries on every notification display is too slow.
# Instead, we cache association mappings (app classes, display names, execs -> icons)
# in a state file. We only rebuild the cache if the modification times of standard
# application directories are newer than the cache file.
ICONS_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
ICONS_CACHE_FILE="$ICONS_CACHE_DIR/window-switcher-icons.cache"
mkdir -p "$ICONS_CACHE_DIR"

declare -A class_to_icon
declare -A name_to_icon
declare -A exec_to_icon

rebuild_cache=false
if [ ! -s "$ICONS_CACHE_FILE" ]; then
  rebuild_cache=true
else
  # Compare directory mtimes with cache file mtime
  max_mtime=0
  for d in "/usr/share/applications" "$HOME/.local/share/applications" "/var/lib/flatpak/exports/share/applications" "$HOME/.local/share/flatpak/exports/share/applications"; do
    if [ -d "$d" ]; then
      mtime=$(stat -c %Y "$d" 2>/dev/null || echo 0)
      if [ "$mtime" -gt "$max_mtime" ]; then
        max_mtime="$mtime"
      fi
    fi
  done
  
  cache_mtime=$(stat -c %Y "$ICONS_CACHE_FILE" 2>/dev/null || echo 0)
  if [ "$max_mtime" -gt "$cache_mtime" ]; then
    rebuild_cache=true
  fi
fi

# Rebuild the desktop entry maps by scanning desktop files.
# awk parses values under the main [Desktop Entry] block to extract Name, Icon, StartupWMClass, and Exec.
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
      BEGIN {
        function process_file(fn_path, icon, wmclass, name, exec) {
          if (icon != "") {
            if (wmclass != "") print "class\t" tolower(wmclass) "\t" icon;
            if (name != "") print "name\t" tolower(name) "\t" icon;
            if (exec != "") print "exec\t" tolower(exec) "\t" icon;
            split(fn_path, fn_parts, "/");
            fn = fn_parts[length(fn_parts)];
            sub(/\.desktop$/, "", fn);
            print "exec\t" tolower(fn) "\t" icon;
          }
        }
        prev_file = "";
      }
      FNR == 1 {
        if (prev_file != "") {
          process_file(prev_file, icon, wmclass, name, exec);
        }
        name=""; icon=""; wmclass=""; exec=""; in_entry=0;
        prev_file = FILENAME;
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
      END {
        if (prev_file != "") {
          process_file(prev_file, icon, wmclass, name, exec);
        }
      }
    ' "${files[@]}" 2>/dev/null || true)
  fi
  
  for k in "${!tmp_class[@]}"; do class_to_icon["$k"]="${tmp_class[$k]}"; done
  for k in "${!tmp_name[@]}"; do name_to_icon["$k"]="${tmp_name[$k]}"; done
  for k in "${!tmp_exec[@]}"; do exec_to_icon["$k"]="${tmp_exec[$k]}"; done
  
  tmp_cache="$ICONS_CACHE_FILE.tmp.$$"
  declare -p class_to_icon name_to_icon exec_to_icon > "$tmp_cache" 2>/dev/null || true
  mv -f "$tmp_cache" "$ICONS_CACHE_FILE" 2>/dev/null || true
  cleanup_stale_tmp_files "$cache_dir"
else
  . "$ICONS_CACHE_FILE"
fi

# guess_icon:
# Maps window title and app class to a corresponding desktop application icon.
# Heuristic cascades: direct app name class lookup -> title matching -> title substrings -> generic default.
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
  
  # 3. Substring search in window title
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
  
  # Generic fallbacks
  if [ -n "$app_lower" ] && [ "$app_lower" != "null" ]; then
    printf '%s' "$app_lower"
  else
    printf 'preferences-desktop-notification-bell'
  fi
}

show_menu() {
    local tab=$'\t'
    mapfile -t parsed_items < <(echo "$notifs" | jq -r --arg t "$tab" '
      to_entries | reverse | .[] | 
      "\((.key + 1))\($t)\(.value.id)\($t)\(.value.app_name)\($t)\(.value.summary)\($t)\(.value.body | gsub("\n"; " ") | .[0:60])"
    ')
    
    if [ "${#parsed_items[@]}" -eq 0 ]; then
        printf "No notification history.\0icon\x1fnotifications-disabled-symbolic\n" | \
            rofi -dmenu -i -p "Notifications:" -show-icons -theme-str "$theme" 2>/dev/null || true
        exit 0
    fi
    
    declare -a item_keys=()
    declare -a item_ids=()
    declare -a item_displays=()
    declare -a item_icons=()
    
    for line in "${parsed_items[@]}"; do
        idx="${line%%$tab*}"
        rest="${line#*$tab}"
        id="${rest%%$tab*}"
        rest="${rest#*$tab}"
        app_name="${rest%%$tab*}"
        rest="${rest#*$tab}"
        summary="${rest%%$tab*}"
        body_preview="${rest#*$tab}"
        
        display_name="${idx}) [${app_name}] ${summary} - ${body_preview}"
        icon_name="$(guess_icon "${app_name} ${summary}" "${app_name}")"
        
        item_keys+=( "$idx" )
        item_ids+=( "$id" )
        item_displays+=( "$display_name" )
        item_icons+=( "$icon_name" )
    done
    
    local clear_display="󰎟  [Clear All History]"
    local clear_icon="edit-clear-symbolic"
    
    selected_val=$(
        {
            for i in "${!item_displays[@]}"; do
                printf "%s\0icon\x1f%s\n" "${item_displays[i]}" "${item_icons[i]}"
            done
            printf "%s\0icon\x1f%s\n" "$clear_display" "$clear_icon"
        } | rofi -dmenu -i -p "Notifications:" -show-icons -theme-str "$theme" 2>/dev/null || true
    )
    
    if [ -z "$selected_val" ]; then
        exit 0
    fi
    
    # Clear All History:
    # We query the KDE notification manager over DBus to close every active notification ID.
    # We then trigger a SIGUSR2 signal to active-window-listener-kde.py so it refreshes its lists.
    if [ "$selected_val" = "$clear_display" ]; then
        for id in "${item_ids[@]}"; do
            timeout 2 qdbus6 org.kde.plasmashell /org/freedesktop/Notifications \
                org.freedesktop.Notifications.CloseNotification "$id" >/dev/null 2>&1 || true
        done
        pkill -USR2 -f "[a]ctive-window-listener-kde.py" >/dev/null 2>&1 || true
        sleep 0.15
        exit 0
    fi
    
    local matched_idx=""
    for i in "${!item_displays[@]}"; do
        if [ "${item_displays[i]}" = "$selected_val" ]; then
            matched_idx="${item_keys[i]}"
            break
        fi
    done
    
    if [ -z "$matched_idx" ]; then
        exit 0
    fi
    
    local json_idx=$((matched_idx - 1))
    
    local item
    item=$(echo "$notifs" | jq -c ".[$json_idx]")
    local id
    id=$(echo "$item" | jq -r '.id')
    local app_name
    app_name=$(echo "$item" | jq -r '.app_name')
    local summary
    summary=$(echo "$item" | jq -r '.summary')
    local body
    body=$(echo "$item" | jq -r '.body')
    local timestamp
    timestamp=$(echo "$item" | jq -r '.timestamp')
    local time_str
    time_str=$(format_locale_datetime "$timestamp")
    
    local actions
    actions=$(printf "Open App/Details\nDismiss Notification\nView Full Message\nBack")
    
    local act
    act=$(printf "%s" "$actions" | rofi -dmenu -i -p "$app_name" -theme-str "$theme" -mesg "<b>$summary</b>\n\n$body\n\nReceived: $time_str" -no-fixed-num-lines 2>/dev/null || true)
    
    case "$act" in
        "Open App/Details")
            # 1. Extract and open URL if present in the notification body
            local url
            url=$(echo "$body" | grep -o -E 'https?://[^"'\''>[:space:]<]+' | head -n 1 || true)
            if [ -n "$url" ]; then
                xdg-open "$url" >/dev/null 2>&1 &
            fi
            
            # 2. Emit DBus ActionInvoked signal to notify the sending application of interaction
            dbus-send --session --type=signal /org/freedesktop/Notifications \
                org.freedesktop.Notifications.ActionInvoked uint32:"$id" string:"default" >/dev/null 2>&1 || true
            
            # 3. Dismiss/Close the notification in plasmashell
            timeout 2 qdbus6 org.kde.plasmashell /org/freedesktop/Notifications \
                org.freedesktop.Notifications.CloseNotification "$id" >/dev/null 2>&1 || true
            sleep 0.15
            ;;
        "Dismiss Notification")
            # Close the notification over DBus and refresh the menu history view
            timeout 2 qdbus6 org.kde.plasmashell /org/freedesktop/Notifications \
                org.freedesktop.Notifications.CloseNotification "$id" >/dev/null 2>&1 || true
            sleep 0.15
            notifs="$(cat "$history_file")"
            count="$(echo "$notifs" | jq 'length')"
            if [ "$count" -gt 0 ]; then
                show_menu
            fi
            ;;
        "View Full Message")
            rofi -e "App: $app_name
Title: $summary
Message: $body
Time: $time_str" -theme-str "$theme" 2>/dev/null || true
            show_menu
            ;;
        "Back")
            show_menu
            ;;
        *)
            exit 0
            ;;
    esac
}

show_menu
