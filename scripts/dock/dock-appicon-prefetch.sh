#!/usr/bin/env bash
# Prefetch dock app icons via appicon and materialize exact-size PNGs for GTK/Waybar.
# Skips apps that already have a warm theme/dock-appicons/<id>.png unless FORCE=1.
# Online resolve (fills ~/.cache/appicon); hot dock paths use --offline against that cache.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/appicon-lib.sh"

manifest="$WAYBAR_HOME/data/dock-apps.json"
link_dir="$WAYBAR_HOME/theme/dock-appicons"
force="${WAYBAR_APPICON_PREFETCH_FORCE:-0}"

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
skipped=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ "$force" != "1" ] && [ -f "$link_dir/${id}.png" ] && [ -s "$link_dir/${id}.png" ]; then
    waybar_appicon_miss_clear "$id" || true
    skipped=$((skipped + 1))
    ok=$((ok + 1))
    continue
  fi

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

  path="$(waybar_appicon_resolve "$query" "$display_size" "$theme" online || true)"
  if [ -n "${path:-}" ] && [ -f "$path" ] \
    && WAYBAR_APPICON_REMATERIALIZE="$force" waybar_appicon_materialize "$path" "$link_dir/$id" "$display_size"; then
    waybar_appicon_miss_clear "$id" || true
    ok=$((ok + 1))
  else
    # Never wipe a previously good PNG on a transient miss.
    if [ -f "$link_dir/${id}.png" ] && [ -s "$link_dir/${id}.png" ]; then
      ok=$((ok + 1))
    else
      waybar_appicon_miss_mark "$id" || true
      fail=$((fail + 1))
    fi
  fi
done < <(jq -r 'keys[]' "$manifest")

echo "dock-appicon prefetch: $ok ok ($skipped cached), $fail missing (bin=$bin size=$display_size)"
