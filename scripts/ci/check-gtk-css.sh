#!/usr/bin/env bash
# Guard GTK3 / Waybar CSS compatibility.
# Waybar's CSS parser rejects several modern CSS features and exits on parse errors
# (see journal: 'font-variant-ligatures' / multi-percentage @keyframes).
#
# Checks:
#   1) Denylist of known-bad ricing props
#   2) Allowlist of GtkCssProvider property names (docs + optional live probe)
#   3) Multi-percentage @keyframes forms
#
# Usage: check-gtk-css.sh [ROOT]
# ROOT defaults to the repo root containing this script.
# Prefer explicit ROOT arg. Do not default to WAYBAR_HOME — generator tests set that
# to a sandbox and would skip scanning the real tree.
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="${1:-$SCRIPT_ROOT}"
cd "$ROOT"

ALLOWLIST="$SCRIPT_ROOT/scripts/ci/lib/gtk3-css-property-allowlist.txt"
fail=0

# Include generated theme CSS — stylelint deliberately ignores *.generated.css.
# Prune theme/rofi (rofi themes are not loaded by Waybar's GtkCssProvider).
mapfile -t css_files < <(
  find . \( -path ./node_modules -o -path ./.git -o -path './theme/rofi' \) -prune -o \
    -type f -name '*.css' -print \
    | sed 's|^\./||' \
    | sort
)

if [ "${#css_files[@]}" -eq 0 ]; then
  echo "FAIL: no CSS files found under $ROOT" >&2
  exit 1
fi

echo "=== gtk/waybar CSS compat (${#css_files[@]} files under $ROOT) ==="

# Properties GtkCssProvider rejects as invalid names (Waybar exits on parse error).
# Allowlist source: https://docs.gtk.org/gtk3/css-properties.html
disallowed_props=(
  'font-variant-ligatures'
  'font-variant-numeric'
  'font-feature-settings'
  'backdrop-filter'
  'filter'
  'transform'
  'width'
  'height'
  'max-width'
  'max-height'
  'overflow'
  'overflow-x'
  'overflow-y'
  'text-overflow'
  'display'
  'flex'
  'gap'
  'position'
  'z-index'
  'line-height'
  'white-space'
  'text-align'
  'box-sizing'
  'cursor'
)

for prop in "${disallowed_props[@]}"; do
  # Use grep (not rg): generator CI images only install jq+dash.
  matches=$(grep -nE "^[[:space:]]*${prop}[[:space:]]*:" "${css_files[@]}" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "FAIL: GTK3/Waybar-unsafe CSS property '${prop}':" >&2
    printf '%s\n' "$matches" >&2
    fail=1
  fi
done

# Multi-percentage keyframe selectors (e.g. "0%, 100% {") crash Waybar's CSS parser.
matches=$(grep -nE \
  -e '^[[:space:]]*[0-9]+%[[:space:]]*,[[:space:]]*[0-9]+%' \
  -e '^[[:space:]]*from[[:space:]]*,[[:space:]]*to' \
  -e '^[[:space:]]*to[[:space:]]*,[[:space:]]*from' \
  "${css_files[@]}" 2>/dev/null || true)
if [ -n "$matches" ]; then
  echo "FAIL: multi-selector @keyframes (use from/to + animation-direction: alternate):" >&2
  printf '%s\n' "$matches" >&2
  fail=1
fi

# --- Allowlist: every declared property must be a known GtkCssProvider name ---
if [ ! -f "$ALLOWLIST" ]; then
  echo "FAIL: missing GTK allowlist at $ALLOWLIST" >&2
  fail=1
else
  echo "Checking declared properties against GTK3 allowlist..."
  unknown=$(
    python3 - "$ALLOWLIST" "${css_files[@]}" <<'PY'
import re, sys
from pathlib import Path

allow = {
    ln.strip().lower()
    for ln in Path(sys.argv[1]).read_text().splitlines()
    if ln.strip() and not ln.strip().startswith("#")
}
prop_re = re.compile(r"^(\s*)([a-zA-Z_-][a-zA-Z0-9_-]*)\s*:", re.M)
skip = {"from", "to", "and", "or"}
unknown = []
for path in sys.argv[2:]:
    text = Path(path).read_text(errors="ignore")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    for m in prop_re.finditer(text):
        name = m.group(2)
        low = name.lower()
        if low in skip or name.startswith("--"):
            continue
        if low not in allow:
            unknown.append(f"{path}:{text[: m.start()].count(chr(10)) + 1}:{name}")
if unknown:
    print("\n".join(sorted(set(unknown))))
PY
  )
  if [ -n "$unknown" ]; then
    echo "FAIL: CSS properties not in GTK3 allowlist (will crash Waybar if invalid):" >&2
    printf '%s\n' "$unknown" >&2
    fail=1
  else
    echo "ok: all declared properties are on the GTK3 allowlist"
  fi
fi

# --- Optional live GtkCssProvider probe (when PyGObject + GTK3 are available) ---
# CssProvider.load_from_data validates property names without Gtk.init / DISPLAY.
if python3 -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk' >/dev/null 2>&1; then
  echo "Probing declared properties with Gtk.CssProvider..."
  probe_out=$(
    python3 - "${css_files[@]}" <<'PY'
import re, sys
from pathlib import Path
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

prop_re = re.compile(r"^(\s*)([a-zA-Z_-][a-zA-Z0-9_-]*)\s*:", re.M)
skip = {"from", "to", "and", "or"}
seen = set()
rejects = []
for path in sys.argv[1:]:
    text = re.sub(r"/\*.*?\*/", "", Path(path).read_text(errors="ignore"), flags=re.S)
    for m in prop_re.finditer(text):
        name = m.group(2)
        low = name.lower()
        if low in skip or name.startswith("--") or low in seen:
            continue
        seen.add(low)
        css = f"#probe {{ {name}: inherit; }}".encode()
        provider = Gtk.CssProvider()
        try:
            provider.load_from_data(css)
        except Exception as e:
            msg = str(e)
            if "is not a valid property name" in msg:
                rejects.append(name)

if rejects:
    print("\n".join(sorted(set(rejects))))
PY
  )
  if [ -n "$probe_out" ]; then
    echo "FAIL: Gtk.CssProvider rejected property names:" >&2
    printf '%s\n' "$probe_out" >&2
    fail=1
  else
    echo "ok: Gtk.CssProvider accepts all declared property names"
  fi
else
  echo "note: Gtk.CssProvider probe skipped (PyGObject GTK3 not installed)"
fi

if [ "$fail" -ne 0 ]; then
  echo "gtk-css-compat: FAILED (Waybar will refuse to start on parse errors)" >&2
  exit 1
fi

echo "ok: gtk/waybar CSS compat clean"
