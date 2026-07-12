#!/usr/bin/env bash
# Apply wallpaper-derived colors into theme/tokens.wallpaper.generated.css.
# No-op (exit 0) unless theme.mode == wallpaper.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck disable=SC1091
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck disable=SC1091
. "$WAYBAR_SCRIPTS/lib/theme-wallpaper-lib.sh"

settings="$WAYBAR_HOME/data/waybar-settings.json"
[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mode="$(jq -r '.theme.mode // "static"' "$settings")"
case "$mode" in
  wallpaper) ;;
  *) exit 0 ;;
esac

backend_cfg="$(jq -r '.theme.wallpaper.backend // "auto"' "$settings")"
scope="$(jq -r '.theme.wallpaper.scope // "per_output"' "$settings")"
fallback_colors="$(jq -c '.theme.colors // {}' "$settings")"

backend="$(waybar_wallpaper_resolve_backend "$backend_cfg")"

theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$theme_dir"
out="$theme_dir/tokens.wallpaper.generated.css"
tmp="${out}.tmp.$$"

{
  printf '%s\n' '/* Wallpaper overlay — written by theme-apply-wallpaper.sh; do not edit by hand */'
  printf '%s\n' "/* backend=${backend:-none} scope=${scope} */"
  printf '\n'
} >"$tmp"

merge_colors() {
  local extracted="${1-}"
  [ -n "$extracted" ] || extracted='{}'
  jq -cn --argjson f "$fallback_colors" --argjson e "$extracted" '
    ($e | with_entries(select(.value != null and .value != ""))) as $ov
    | $f + $ov
  ' 2>/dev/null || printf '%s' "$fallback_colors"
}

emit_for_image() {
  local class="$1" image="$2"
  local extracted colors
  if [ -n "$image" ]; then
    extracted="$(waybar_wallpaper_extract_colors "$image" "$backend")"
  else
    extracted="{}"
  fi
  colors="$(merge_colors "$extracted")"
  waybar_wallpaper_emit_css_block "$class" "$colors"
}

case "$scope" in
  global)
    # Single extraction: first available output path, else global image, else fallback colors only.
    first_out=""
    first_img=""
    while IFS= read -r out_name; do
      [ -n "$out_name" ] || continue
      first_out="$out_name"
      first_img="$(waybar_wallpaper_path_for_output "$out_name")"
      [ -n "$first_img" ] && break
    done <<EOF
$(waybar_list_outputs)
EOF
    if [ -z "$first_img" ]; then
      first_img="$(jq -r '.theme.wallpaper.image // empty' "$settings")"
      case "$first_img" in null | "") first_img="" ;; esac
    fi
    emit_for_image "" "$first_img" >>"$tmp"
    ;;
  *)
    # per_output (default): one CSS block per connected output.
    while IFS= read -r out_name; do
      [ -n "$out_name" ] || continue
      css_class="$(waybar_css_class_for_output "$out_name")"
      img="$(waybar_wallpaper_path_for_output "$out_name")"
      emit_for_image "$css_class" "$img" >>"$tmp"
    done <<EOF
$(waybar_list_outputs)
EOF
    ;;
esac

mv -f "$tmp" "$out"
