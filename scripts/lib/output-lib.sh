#!/usr/bin/env sh
# Output / monitor helpers for Waybar (list, CSS class, scroll-per-output).
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# Print one output name per line. Probe backends in order until one yields names.
# When WAYBAR_TEST_OUTPUTS is set (comma-separated), it wins — hermetic CI fixtures.
waybar_list_outputs() {
  _names=""

  if [ -n "${WAYBAR_TEST_OUTPUTS:-}" ]; then
    _names=$(printf '%s' "$WAYBAR_TEST_OUTPUTS" | tr ',' '\n')
    printf '%s\n' "$_names" | sed '/^$/d'
    return 0
  fi

  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    _names=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)
  fi

  if [ -z "$_names" ] && command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    _names=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)
  fi

  if [ -z "$_names" ] && command -v wlr-randr >/dev/null 2>&1; then
    # Non-indented lines start with the output name.
    _names=$(wlr-randr 2>/dev/null | awk '/^[^[:space:]]/ { print $1 }' || true)
  fi

  if [ -z "$_names" ] && command -v kscreen-doctor >/dev/null 2>&1; then
    # Best-effort: "Output: NAME" or "Output: N NAME"
    _names=$(
      kscreen-doctor -o 2>/dev/null \
        | sed -n 's/^[[:space:]]*Output:[[:space:]]*//p' \
        | awk '{ print $NF }' \
        || true
    )
  fi

  printf '%s\n' "$_names" | sed '/^$/d'
}

# Sanitize an output name to a CSS-safe class token.
waybar_css_class_for_output() {
  _name="${1:-}"
  _safe=$(printf '%s' "$_name" | sed 's/[^A-Za-z0-9_-]/_/g')
  if [ -z "$_safe" ]; then
    _hash=$(printf '%s' "$_name" | cksum 2>/dev/null | awk '{ print $1 }' || printf '0')
    _safe="out_${_hash}"
  fi
  printf '%s' "$_safe"
}

# Return 0 if workspaces.scroll_per_output is true/absent (default true).
waybar_scroll_per_output_enabled() {
  _val="true"
  if type waybar_settings_get >/dev/null 2>&1; then
    _val=$(waybar_settings_get '.workspaces.scroll_per_output' 'true')
  elif [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ] && command -v bash >/dev/null 2>&1; then
    _val=$(
      bash -c 'WAYBAR_HOME="$1"; WAYBAR_SCRIPTS="$2"; . "$2/lib/waybar-settings.sh"; waybar_settings_get ".workspaces.scroll_per_output" "true"' \
        _ "$WAYBAR_HOME" "$WAYBAR_SCRIPTS" 2>/dev/null || printf 'true'
    )
  fi
  case "$_val" in
    false | False | FALSE | 0 | no | No | NO | null | off | Off | OFF) return 1 ;;
    *) return 0 ;;
  esac
}
