#!/usr/bin/env bash
# Settings helpers for Waybar.
#
# Source of truth: data/waybar-settings.jsonc
# Compiled artifact: data/waybar-settings.json (overwritten from jsonc on load)
# Optional secrets overlay: data/waybar-secrets.jsonc (gitignored; merged at read time)
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
WAYBAR_SETTINGS="${WAYBAR_SETTINGS:-$WAYBAR_HOME/data/waybar-settings.json}"
WAYBAR_SETTINGS_JSONC="${WAYBAR_SETTINGS_JSONC:-${WAYBAR_SETTINGS}c}"
WAYBAR_SECRETS="${WAYBAR_SECRETS:-$WAYBAR_HOME/data/waybar-secrets.json}"
WAYBAR_SECRETS_JSONC="${WAYBAR_SECRETS_JSONC:-${WAYBAR_SECRETS}c}"
WAYBAR_SERVICES_LEGACY="${WAYBAR_HOME}/data/waybar-services.json"

strip_jsonc_comments() {
  local input_file="$1"
  if [[ -f "$input_file" ]]; then
    perl -0777 -pe 's/\/\*.*?\*\///sg; s/(?<!:)\/\/.*//g' "$input_file" 2>/dev/null || cat "$input_file"
  fi
}

compile_jsonc_settings() {
  local json_file="$WAYBAR_SETTINGS"
  local jsonc_file="$WAYBAR_SETTINGS_JSONC"

  local base_dir
  base_dir=$(dirname "$json_file")
  mkdir -p "$base_dir"

  # Prefer jsonc as the only editable source; always compile it to json.
  # (mtime short-circuits break restore/replace flows where .json outlives .jsonc.)
  if [[ -f "$jsonc_file" ]]; then
    strip_jsonc_comments "$jsonc_file" > "$json_file" 2>/dev/null || true
  elif [[ -f "$json_file" ]]; then
    # One-time bootstrap: promote commented json to jsonc, then strip json.
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

# Emit settings JSON with optional secrets overlay merged on top (deep merge).
# Secrets are never written into waybar-settings.json.
waybar_settings_merged_json() {
  local settings_json="{}"
  local secrets_json="{}"
  local file
  file="$(waybar_settings_file)"

  if [[ -f "$file" ]]; then
    settings_json=$(strip_jsonc_comments "$file" 2>/dev/null || cat "$file" 2>/dev/null || echo "{}")
    [[ -n "$settings_json" ]] || settings_json="{}"
  fi

  if [[ -f "$WAYBAR_SECRETS_JSONC" ]]; then
    secrets_json=$(strip_jsonc_comments "$WAYBAR_SECRETS_JSONC" 2>/dev/null || echo "{}")
  elif [[ -f "$WAYBAR_SECRETS" ]]; then
    secrets_json=$(strip_jsonc_comments "$WAYBAR_SECRETS" 2>/dev/null || cat "$WAYBAR_SECRETS" 2>/dev/null || echo "{}")
  fi
  [[ -n "$secrets_json" ]] || secrets_json="{}"

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s' "$settings_json"
    return
  fi

  jq -s '.[0] * (.[1] // {})' \
    <(printf '%s' "$settings_json") \
    <(printf '%s' "$secrets_json") 2>/dev/null \
    || printf '%s' "$settings_json"
}

waybar_settings_get() {
  local path="$1"
  local default="${2:-}"

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s' "$default"
    return
  fi

  local merged
  merged="$(waybar_settings_merged_json)"
  [[ -n "$merged" ]] || merged="{}"

  printf '%s' "$merged" | jq -r --arg default "$default" "if ($path != null) then $path else \$default end" 2>/dev/null || printf '%s' "$default"
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

waybar_module_interval() {
  local key="$1"
  local fallback="${2:-0}"
  local value
  # Canonical map is module_intervals; poll_intervals kept as read fallback only.
  value="$(waybar_settings_get ".module_intervals.${key}" "")"
  if [[ -z "$value" || "$value" == "null" ]]; then
    value="$(waybar_settings_get ".poll_intervals.${key}" "$fallback")"
  fi
  # Signal-driven modules: keep a long cache TTL so library callers do not re-probe.
  if [[ "$value" == "once" ]]; then
    printf '86400'
    return
  fi
  if [[ -z "$value" || "$value" == "null" ]]; then
    printf '%s' "$fallback"
    return
  fi
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

# Back-compat alias used by older scripts/docs.
waybar_poll_interval() {
  waybar_module_interval "$@"
}
