#!/usr/bin/env bash
# Fast GTK3 CSS smoke for waybar-launch: load theme.css (or style.css) like Waybar.
# Exit 0 if clean / Gtk unavailable; exit 1 if Gtk rejects CSS (would crash Waybar).
# Usage: waybar-gtk-css-smoke.sh [WAYBAR_HOME]
set -euo pipefail

ROOT="${1:-${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}}"

if ! python3 -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk' >/dev/null 2>&1; then
  exit 0
fi

python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

root = Path(sys.argv[1])
# Prefer theme.css (full import chain Waybar uses via style.css → theme.css).
candidates = [root / "theme.css", root / "style.css"]
target = next((p for p in candidates if p.is_file()), None)
if target is None:
    sys.exit(0)

# Static denylist (no Gtk needed for these — catch even if import chain is huge).
import re
bad = []
for path in root.rglob("*.css"):
    if "theme/rofi" in path.as_posix() or "node_modules" in path.as_posix():
        continue
    text = re.sub(r"/\*.*?\*/", "", path.read_text(errors="ignore"), flags=re.S)
    if re.search(r"(^|[\s,}])(:root)(\s*[,{])", text, re.M):
        bad.append(f"{path.relative_to(root)}: :root")
    if re.search(r"\bvar\s*\(", text):
        bad.append(f"{path.relative_to(root)}: var()")
    if re.search(r"(^|\n)\s*--[A-Za-z0-9_-]+\s*:", text):
        bad.append(f"{path.relative_to(root)}: custom property")
if bad:
    print("GTK3-unsafe CSS (would crash Waybar):", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)

provider = Gtk.CssProvider()
try:
    provider.load_from_path(str(target))
except Exception as exc:
    print(f"Gtk.CssProvider rejected {target.name}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
