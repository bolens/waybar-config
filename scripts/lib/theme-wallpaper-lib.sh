#!/usr/bin/env sh
# Wallpaper → theme.colors helpers (matugen / wallust / pywal).
# Builds on output-lib.sh. CI: WAYBAR_TEST_OUTPUTS, WAYBAR_TEST_COLORS_MAP.
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck disable=SC1091
. "$WAYBAR_SCRIPTS/lib/output-lib.sh"

# Resolve color-extraction backend. Prefer explicit pin; auto probes matugen → wallust → pywal/pywal16.
# Prints backend name or empty when none available.
waybar_wallpaper_resolve_backend() {
  _want="${1:-}"
  if [ -z "$_want" ] || [ "$_want" = "null" ]; then
    _want="auto"
  fi

  case "$_want" in
    auto)
      if command -v matugen >/dev/null 2>&1; then
        printf '%s' "matugen"
        return 0
      fi
      if command -v wallust >/dev/null 2>&1; then
        printf '%s' "wallust"
        return 0
      fi
      if command -v pywal >/dev/null 2>&1; then
        printf '%s' "pywal"
        return 0
      fi
      if command -v pywal16 >/dev/null 2>&1; then
        printf '%s' "pywal16"
        return 0
      fi
      if command -v wal >/dev/null 2>&1; then
        printf '%s' "pywal"
        return 0
      fi
      printf ''
      return 0
      ;;
    matugen | wallust | pywal | pywal16)
      printf '%s' "$_want"
      return 0
      ;;
    *)
      printf ''
      return 0
      ;;
  esac
}

# Best-effort wallpaper path for one output from a compositor.
_waybar_wallpaper_query_compositor() {
  _out="${1:-}"
  _path=""

  if command -v swww >/dev/null 2>&1; then
    # Typical: "DP-1: image: /path/to/wall.jpg" or namespace JSON variants.
    _path=$(
      swww query 2>/dev/null \
        | awk -v o="$_out" '
            $0 ~ ("^" o ":") || $0 ~ ("output:.*" o) {
              for (i = 1; i <= NF; i++) {
                if ($i ~ /^\//) { print $i; exit }
              }
            }
          ' || true
    )
  fi

  if [ -z "$_path" ] && command -v hyprctl >/dev/null 2>&1; then
    # hyprpaper listactive (newer) or hyprctl hyprpaper wallpaper
    if command -v jq >/dev/null 2>&1; then
      _path=$(
        hyprctl hyprpaper listactive -j 2>/dev/null \
          | jq -r --arg o "$_out" '
              if type == "object" then
                .[$o] // .[($o|ascii_downcase)] // empty
              elif type == "array" then
                (map(select(.monitor == $o or .output == $o)) | .[0].wallpaper // .[0].path // empty)
              else empty end
            ' 2>/dev/null || true
      )
    fi
    if [ -z "$_path" ]; then
      _path=$(
        hyprctl hyprpaper listactive 2>/dev/null \
          | awk -v o="$_out" -F'[=,]' '
              $0 ~ o {
                for (i = 1; i <= NF; i++) {
                  gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
                  if ($i ~ /^\//) { print $i; exit }
                }
              }
            ' || true
      )
    fi
  fi

  if [ -z "$_path" ] && command -v qdbus >/dev/null 2>&1; then
    _path=$(
      qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.wallpaper 2>/dev/null \
        | awk -v o="$_out" '
            $0 ~ o && $0 ~ /\// {
              for (i = 1; i <= NF; i++) if ($i ~ /^\//) { print $i; exit }
            }
          ' || true
    )
  fi
  if [ -z "$_path" ] && command -v qdbus6 >/dev/null 2>&1; then
    _path=$(
      qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.wallpaper 2>/dev/null \
        | awk -v o="$_out" '
            $0 ~ o && $0 ~ /\// {
              for (i = 1; i <= NF; i++) if ($i ~ /^\//) { print $i; exit }
            }
          ' || true
    )
  fi

  # Strip quotes / trailing commas from best-effort parses.
  _path=$(printf '%s' "$_path" | sed 's/^["'\'']//; s/["'\'',]$//; s/[[:space:]]*$//')
  if [ -n "$_path" ] && [ -f "$_path" ]; then
    printf '%s' "$_path"
  fi
}

# Resolve wallpaper image for OUTPUT.
# Order: theme.wallpaper.outputs.<name> → swww/hyprpaper/plasma → theme.wallpaper.image
waybar_wallpaper_path_for_output() {
  _output="${1:-}"
  _settings="${WAYBAR_HOME}/data/waybar-settings.json"
  _pin=""
  _global=""

  if [ -f "$_settings" ] && command -v jq >/dev/null 2>&1; then
    _pin=$(jq -r --arg o "$_output" '.theme.wallpaper.outputs[$o] // empty' "$_settings" 2>/dev/null || true)
    _global=$(jq -r '.theme.wallpaper.image // empty' "$_settings" 2>/dev/null || true)
    case "$_global" in null | "") _global="" ;; esac
    case "$_pin" in null | "") _pin="" ;; esac
  fi

  if [ -n "$_pin" ] && [ -f "$_pin" ]; then
    printf '%s' "$_pin"
    return 0
  fi

  _comp=$(_waybar_wallpaper_query_compositor "$_output")
  if [ -n "$_comp" ]; then
    printf '%s' "$_comp"
    return 0
  fi

  if [ -n "$_global" ] && [ -f "$_global" ]; then
    printf '%s' "$_global"
    return 0
  fi

  printf ''
}

# Map a free-form palette JSON blob into theme.colors keys (best-effort).
_waybar_wallpaper_normalize_colors() {
  # Never use ${var:-{}} — the first } closes the expansion and appends a stray }.
  if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    _raw="$1"
  else
    _raw='{}'
  fi
  command -v jq >/dev/null 2>&1 || {
    printf '%s' '{}'
    return 0
  }
  # shellcheck disable=SC2016
  printf '%s' "$_raw" | jq -c '
    def hexify:
      if type == "string" then .
      elif type == "object" then (.hex // .color // .value // .rgb // empty)
      else empty end;
    def first_hex($obj; $keys):
      reduce $keys[] as $k (
        null;
        if . != null then . else ($obj[$k] | hexify // null) end
      );
    . as $r
    | (if ($r|type) == "object" and ($r.colors|type) == "object" then $r.colors else $r end) as $c
    | (if ($c.dark|type) == "object" then $c.dark
       elif ($c.colors|type) == "object" then $c.colors
       else $c end) as $p
    | ( $p
        + (if ($p.special|type) == "object" then $p.special else {} end)
        + (if ($p.colors|type) == "object" then $p.colors else {} end)
      ) as $flat
    | {
        foreground: (first_hex($flat; ["foreground","on_background","on_surface","text","color7"]) // null),
        background: (first_hex($flat; ["background","surface","color0"]) // null),
        border: (first_hex($flat; ["border","outline","primary","color4"]) // null),
        accent: (first_hex($flat; ["accent","primary","secondary","color5"]) // null),
        warning: (first_hex($flat; ["warning","tertiary","color3"]) // null),
        critical: (first_hex($flat; ["critical","error","color1"]) // null),
        tooltip_background: (first_hex($flat; ["tooltip_background","surface_container","background","color0"]) // null),
        tooltip_border: (first_hex($flat; ["tooltip_border","outline","border","color8"]) // null),
        workspace_active: (first_hex($flat; ["workspace_active","primary_container","primary","color5","accent"]) // null),
        workspace_inactive: (first_hex($flat; ["workspace_inactive","on_surface_variant","color8"]) // null),
        workspace_visible: (first_hex($flat; ["workspace_visible","secondary","color6"]) // null)
      }
    | with_entries(select(.value != null and .value != ""))
  ' || printf '%s' '{}'
}

# Extract colors from IMAGE using BACKEND. Emits JSON matching theme.colors keys.
# WAYBAR_TEST_COLORS_MAP: JSON object keyed by absolute path or basename → color map (CI).
# Missing backend / failed extract → {}.
waybar_wallpaper_extract_colors() {
  _image="${1:-}"
  _backend="${2:-}"
  _raw='{}'

  if [ -n "${WAYBAR_TEST_COLORS_MAP:-}" ] && command -v jq >/dev/null 2>&1; then
    _base=$(basename "$_image" 2>/dev/null || printf '%s' "$_image")
    _mapped=$(
      printf '%s' "$WAYBAR_TEST_COLORS_MAP" | jq -c --arg p "$_image" --arg b "$_base" '
        .[$p] // .[$b] // empty
      ' 2>/dev/null || true
    )
    if [ -n "$_mapped" ] && [ "$_mapped" != "null" ]; then
      _waybar_wallpaper_normalize_colors "$_mapped"
      return 0
    fi
  fi

  if [ -z "$_image" ] || [ ! -f "$_image" ]; then
    printf '%s' '{}'
    return 0
  fi

  case "$_backend" in
    matugen)
      if command -v matugen >/dev/null 2>&1; then
        _raw=$(matugen image "$_image" --json hex 2>/dev/null || matugen image "$_image" --json 2>/dev/null || printf '%s' '{}')
      fi
      ;;
    wallust)
      if command -v wallust >/dev/null 2>&1; then
        _raw=$(wallust run "$_image" --dump-json 2>/dev/null || wallust run "$_image" -j 2>/dev/null || printf '%s' '{}')
        if [ -z "$_raw" ] || [ "$_raw" = "{}" ]; then
          _cache="${XDG_CACHE_HOME:-$HOME/.cache}/wallust/colors.json"
          [ -f "$_cache" ] && _raw=$(cat "$_cache" 2>/dev/null || printf '%s' '{}')
        fi
      fi
      ;;
    pywal | pywal16)
      _wal_bin=""
      if [ "$_backend" = "pywal16" ] && command -v pywal16 >/dev/null 2>&1; then
        _wal_bin="pywal16"
      elif command -v pywal >/dev/null 2>&1; then
        _wal_bin="pywal"
      elif command -v wal >/dev/null 2>&1; then
        _wal_bin="wal"
      fi
      if [ -n "$_wal_bin" ]; then
        "$_wal_bin" -i "$_image" -n -e -q 2>/dev/null || true
        _cache="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json"
        [ -f "$_cache" ] && _raw=$(cat "$_cache" 2>/dev/null || printf '%s' '{}')
      fi
      ;;
    *)
      _raw='{}'
      ;;
  esac

  [ -n "$_raw" ] || _raw='{}'
  _waybar_wallpaper_normalize_colors "$_raw"
}

# Emit CSS for one output class (empty class → unscoped / global).
# COLORS_JSON: partial or full theme.colors map.
waybar_wallpaper_emit_css_block() {
  _class="${1:-}"
  if [ "$#" -ge 2 ] && [ -n "$2" ]; then
    _colors="$2"
  else
    _colors='{}'
  fi
  command -v jq >/dev/null 2>&1 || return 0

  _bg=$(printf '%s' "$_colors" | jq -r '.background // empty' 2>/dev/null || true)
  _fg=$(printf '%s' "$_colors" | jq -r '.foreground // empty' 2>/dev/null || true)
  _border=$(printf '%s' "$_colors" | jq -r '.border // empty' 2>/dev/null || true)
  _ws_active=$(printf '%s' "$_colors" | jq -r '.workspace_active // empty' 2>/dev/null || true)
  _ws_inactive=$(printf '%s' "$_colors" | jq -r '.workspace_inactive // empty' 2>/dev/null || true)
  _ws_visible=$(printf '%s' "$_colors" | jq -r '.workspace_visible // empty' 2>/dev/null || true)

  if [ -z "$_bg$_fg$_border$_ws_active$_ws_inactive$_ws_visible" ]; then
    return 0
  fi

  if [ -n "$_class" ]; then
    _win="window.${_class}#waybar"
    _scope="window.${_class}#waybar"
  else
    _win="window#waybar"
    _scope="window#waybar"
  fi

  printf '%s\n' "/* wallpaper theme${_class:+ for ${_class}} */"
  printf '%s {\n' "$_win"
  [ -n "$_bg" ] && printf '    background: %s;\n' "$_bg"
  [ -n "$_border" ] && printf '    border-color: %s;\n' "$_border"
  [ -n "$_fg" ] && printf '    color: %s;\n' "$_fg"
  printf '}\n\n'

  if [ -n "$_ws_active" ] || [ -n "$_ws_inactive" ] || [ -n "$_ws_visible" ]; then
    _i=0
    _active_sels=""
    _inactive_sels=""
    _visible_sels=""
    while [ "$_i" -le 9 ]; do
      _active_sels="${_active_sels}${_active_sels:+, }${_scope} #custom-ws-${_i}.ws-active"
      _inactive_sels="${_inactive_sels}${_inactive_sels:+, }${_scope} #custom-ws-${_i}.ws-inactive"
      _visible_sels="${_visible_sels}${_visible_sels:+, }${_scope} #custom-ws-${_i}.ws-visible"
      _i=$((_i + 1))
    done
    if [ -n "$_ws_active" ]; then
      printf '%s {\n    background: %s;\n}\n\n' "$_active_sels" "$_ws_active"
    fi
    if [ -n "$_ws_inactive" ]; then
      printf '%s {\n    color: %s;\n}\n\n' "$_inactive_sels" "$_ws_inactive"
    fi
    if [ -n "$_ws_visible" ]; then
      printf '%s {\n    color: %s;\n}\n\n' "$_visible_sels" "$_ws_visible"
    fi
  fi
}
