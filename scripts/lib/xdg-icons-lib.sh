#!/usr/bin/env bash
# Shared desktop-file → icon map + guess_icon (window-switcher / kde-notifications-rofi).
# Requires: xdg-applications.sh (xdg_application_dirs), bash associative arrays.
# Optional: cleanup_stale_tmp_files from waybar-cache-helpers.sh

: "${WAYBAR_SCRIPTS:=${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts}"

# shellcheck source=xdg-applications.sh
. "$WAYBAR_SCRIPTS/lib/xdg-applications.sh"

# Load or rebuild class_to_icon / name_to_icon / exec_to_icon into the caller's shell.
# Usage: xdg_icons_load_maps [cache_file]
xdg_icons_load_maps() {
  local cache_file="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/window-switcher-icons.cache}"
  local cache_dir
  cache_dir=$(dirname "$cache_file")
  mkdir -p "$cache_dir"

  declare -gA class_to_icon=()
  declare -gA name_to_icon=()
  declare -gA exec_to_icon=()

  local rebuild_cache=false
  if [ ! -s "$cache_file" ]; then
    rebuild_cache=true
  else
    local max_mtime=0 mtime cache_mtime d
    while IFS= read -r d; do
      [ -d "$d" ] || continue
      mtime=$(stat -c %Y "$d" 2>/dev/null || echo 0)
      if [ "$mtime" -gt "$max_mtime" ]; then
        max_mtime="$mtime"
      fi
    done < <(xdg_application_dirs)

    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    if [ "$max_mtime" -gt "$cache_mtime" ]; then
      rebuild_cache=true
    fi
  fi

  if [ "$rebuild_cache" = true ]; then
    local -a files=()
    local d
    shopt -s nullglob
    while IFS= read -r d; do
      [ -d "$d" ] || continue
      files+=("$d"/*.desktop)
    done < <(xdg_application_dirs)
    shopt -u nullglob

    local -A tmp_class=() tmp_name=() tmp_exec=()
    local tab=$'\t' type key val k
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

    local tmp_cache="$cache_file.tmp.$$"
    declare -p class_to_icon name_to_icon exec_to_icon >"$tmp_cache" 2>/dev/null || true
    mv -f "$tmp_cache" "$cache_file" 2>/dev/null || true
    if command -v cleanup_stale_tmp_files >/dev/null 2>&1; then
      cleanup_stale_tmp_files "$cache_dir"
    fi
  else
    # shellcheck source=/dev/null
    . "$cache_file"
  fi
}

# guess_icon: map window title + app class to a desktop icon name.
guess_icon() {
  local title="$1"
  local app="$2"

  local app_lower
  app_lower=$(echo "${app:-}" | tr '[:upper:]' '[:lower:]')
  local title_lower
  title_lower=$(echo "${title:-}" | tr '[:upper:]' '[:lower:]')

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

  if [ -n "${name_to_icon[$title_lower]:-}" ]; then
    printf '%s' "${name_to_icon[$title_lower]}"
    return
  fi
  if [ -n "${class_to_icon[$title_lower]:-}" ]; then
    printf '%s' "${class_to_icon[$title_lower]}"
    return
  fi

  local class_key name_key exec_key
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

  if [[ "$title" =~ ^[~/] || "$title_lower" == *"bash"* || "$title_lower" == *"sh"* || "$title_lower" == *"agy"* ]]; then
    if [ -n "${exec_to_icon["ghostty"]:-}" ]; then
      printf '%s' "${exec_to_icon["ghostty"]}"
      return
    fi
  fi

  if [ -n "$app_lower" ] && [ "$app_lower" != "null" ]; then
    printf '%s' "$app_lower"
  else
    printf 'applications-other'
  fi
}
