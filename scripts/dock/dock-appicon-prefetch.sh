#!/usr/bin/env bash
# Prefetch dock app icons via appicon and materialize exact-size PNGs for GTK/Waybar.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/appicon-lib.sh"

manifest="$WAYBAR_HOME/data/dock-apps.json"
link_dir="$WAYBAR_HOME/theme/dock-appicons"

if ! waybar_appicon_enabled; then
  echo "icons.appicon disabled — skip prefetch" >&2
  exit 0
fi

bin="$(waybar_appicon_bin)" || {
  echo "appicon not found (make install-appicon) — skip prefetch" >&2
  exit 0
}

[ -f "$manifest" ] || exit 0
mkdir -p "$link_dir"

display_size="$(waybar_settings_get '.icons.appicon.size' '18')"
theme="$(waybar_settings_get '.icons.appicon.theme' 'dark')"

ok=0
fail=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  query="$(jq -r --arg id "$id" '
    .[$id]
    | if . == null then empty
      else (
        .appicon
        // .launch
        // (.process_names[0] // empty)
        // (.wm_classes[0] // empty)
        // $id
      )
      end
  ' "$manifest")"
  [ -n "$query" ] || query="$id"
  path="$("$bin" resolve --format png --size "$display_size" --theme "$theme" "$query" 2>/dev/null || true)"
  if [ -n "$path" ] && [ -f "$path" ] && waybar_appicon_materialize "$path" "$link_dir/$id" "$display_size"; then
    ok=$((ok + 1))
  else
    rm -f "$link_dir/$id" "$link_dir/$id.png" 2>/dev/null || true
    fail=$((fail + 1))
  fi
done < <(jq -r 'keys[]' "$manifest")

echo "dock-appicon prefetch: $ok ok, $fail missing (bin=$bin size=$display_size)"
