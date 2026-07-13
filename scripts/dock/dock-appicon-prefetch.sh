#!/usr/bin/env bash
# Prefetch dock app icons via appicon and materialize exact-size PNGs for GTK/Waybar.
# Skips apps that already have a warm theme/dock-appicons/<id>.png unless FORCE=1.
#
# Consumer contract (bolens/appicon):
#   1) one-shot online warm: appicon prefetch [--theme] <queries...>
#   2) materialize via resolve --offline --format png (hot path never opens the network)
# Falls back to per-query online resolve when prefetch is unavailable or offline misses.
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

# Build id→query map and the work list (missing PNGs, or all when FORCE=1).
declare -A APPICON_QUERY=()
work_ids=()
work_queries=()
cached=0

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
  APPICON_QUERY["$id"]="$query"

  if [ "$force" != "1" ] && [ -f "$link_dir/${id}.png" ] && [ -s "$link_dir/${id}.png" ]; then
    waybar_appicon_miss_clear "$id" || true
    cached=$((cached + 1))
    continue
  fi
  work_ids+=("$id")
  work_queries+=("$query")
done < <(jq -r 'keys[]' "$manifest")

# One-shot online warm (batch). Ignore failures — resolve below still tries.
if [ "${#work_queries[@]}" -gt 0 ]; then
  if ! "$bin" prefetch --theme "$theme" "${work_queries[@]}" >/dev/null 2>&1; then
    "$bin" prefetch "${work_queries[@]}" >/dev/null 2>&1 || true
  fi
  # Optional: also warm from installed .desktop files (long-tail for dock-windows).
  if [ "${WAYBAR_APPICON_FROM_DESKTOP:-0}" = "1" ]; then
    "$bin" prefetch --from-desktop --theme "$theme" >/dev/null 2>&1 \
      || "$bin" prefetch --from-desktop >/dev/null 2>&1 \
      || true
  fi
fi

ok=$cached
fail=0
for id in "${work_ids[@]+"${work_ids[@]}"}"; do
  [ -n "$id" ] || continue
  query="${APPICON_QUERY[$id]}"

  # Prefer offline after prefetch warm; fall back to online for cold/miss.
  path="$(waybar_appicon_resolve "$query" "$display_size" "$theme" offline || true)"
  if [ -z "${path:-}" ] || [ ! -f "$path" ]; then
    path="$(waybar_appicon_resolve "$query" "$display_size" "$theme" online || true)"
  fi

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
done

echo "dock-appicon prefetch: $ok ok ($cached cached), $fail missing (bin=$bin size=$display_size)"
