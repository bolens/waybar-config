#!/usr/bin/env bash
# Read ${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/data/waybar-settings.json with sane fallbacks.
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
WAYBAR_SETTINGS="${WAYBAR_SETTINGS:-$WAYBAR_HOME/data/waybar-settings.json}"
WAYBAR_SERVICES_LEGACY="${WAYBAR_HOME}/data/waybar-services.json"

strip_jsonc_comments() {
  local input_file="$1"
  if [[ -f "$input_file" ]]; then
    perl -0777 -pe 's/\/\*.*?\*\///sg; s/(?<!:)\/\/.*//g' "$input_file" 2>/dev/null || cat "$input_file"
  fi
}

compile_jsonc_settings() {
  local json_file="$WAYBAR_SETTINGS"
  local jsonc_file="${WAYBAR_SETTINGS}c"

  local base_dir
  base_dir=$(dirname "$json_file")
  mkdir -p "$base_dir"

  if [[ -f "$jsonc_file" ]]; then
    strip_jsonc_comments "$jsonc_file" > "$json_file" 2>/dev/null || true
  elif [[ -f "$json_file" ]]; then
    local original
    local stripped
    original=$(cat "$json_file" 2>/dev/null || true)
    stripped=$(strip_jsonc_comments "$json_file" 2>/dev/null || true)
    if [[ "$original" != "$stripped" && -n "$stripped" ]]; then
      cp "$json_file" "$jsonc_file" 2>/dev/null || true
      printf '%s\n' "$stripped" > "$json_file" 2>/dev/null || true
    fi
  fi
}

compile_jsonc_settings

waybar_settings_file() {
  printf '%s' "$WAYBAR_SETTINGS"
}

waybar_settings_get() {
  local path="$1"
  local default="${2:-}"
  local file
  file="$(waybar_settings_file)"

  if [[ ! -f "$file" ]] || ! command -v jq >/dev/null 2>&1; then
    printf '%s' "$default"
    return
  fi

  local clean_json
  if ! clean_json=$(strip_jsonc_comments "$file" 2>/dev/null) || [[ -z "$clean_json" ]]; then
    clean_json=$(cat "$file" 2>/dev/null || echo "{}")
  fi

  printf '%s' "$clean_json" | jq -r --arg default "$default" "$path // \$default" 2>/dev/null || printf '%s' "$default"
}

waybar_services_nut_target() {
  local target
  target="$(waybar_settings_get '.services.ups.nut_target' '')"
  if [[ -n "$target" && "$target" != "null" ]]; then
    printf '%s' "$target"
    return
  fi

  if [[ -f "$WAYBAR_SERVICES_LEGACY" ]] && command -v jq >/dev/null 2>&1; then
    jq -r '.ups.nut_target // "ups@127.0.0.1:3493"' "$WAYBAR_SERVICES_LEGACY" 2>/dev/null || true
    return
  fi

  printf 'ups@127.0.0.1:3493'
}

waybar_poll_interval() {
  local key="$1"
  local fallback="${2:-0}"
  local value
  value="$(waybar_settings_get ".poll_intervals.${key}" "$fallback")"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}
