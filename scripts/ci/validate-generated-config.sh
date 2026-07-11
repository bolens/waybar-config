#!/usr/bin/env bash
# Validate Waybar JSONC files parse as JSON (generated + key includes).
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
fail=0

strip_jsonc() {
  python3 - "$1" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
json.loads(text)
PY
}

files=(
  "$WAYBAR_HOME"/modules/*.generated.jsonc
  "$WAYBAR_HOME"/includes/bar-defaults.generated.jsonc
  "$WAYBAR_HOME"/includes/modules.jsonc
  "$WAYBAR_HOME"/includes/stack.jsonc
  "$WAYBAR_HOME"/layouts/*.generated.jsonc
  "$WAYBAR_HOME"/layouts/top.jsonc
  "$WAYBAR_HOME"/layouts/bottom.jsonc
  "$WAYBAR_HOME"/config.jsonc
)

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  if strip_jsonc "$file" 2>/dev/null; then
    printf 'ok %s\n' "$file"
  else
    printf 'FAIL %s\n' "$file" >&2
    fail=1
  fi
  # Generators must emit $WAYBAR_HOME/…, never absolute home paths.
  if grep -E '/home/|~/\.config/waybar' "$file" >/dev/null 2>&1; then
    printf 'FAIL %s contains hardcoded user path (use $WAYBAR_HOME)\n' "$file" >&2
    grep -n -E '/home/|~/\.config/waybar' "$file" >&2 || true
    fail=1
  fi
  # Expanded sandbox paths (/tmp/…) also break portability — require literal $WAYBAR_HOME
  # whenever a scripts/ path appears.
  if grep -E 'scripts/' "$file" >/dev/null 2>&1 && ! grep -F '$WAYBAR_HOME' "$file" >/dev/null 2>&1; then
    printf 'FAIL %s references scripts/ without $WAYBAR_HOME\n' "$file" >&2
    fail=1
  fi
  if grep -E '"(/tmp/|/var/tmp/)' "$file" >/dev/null 2>&1; then
    printf 'FAIL %s contains absolute /tmp path in generated config\n' "$file" >&2
    fail=1
  fi
  # Flat post-reorg paths: scripts/foo.sh (no domain folder) → No such file at runtime.
  if grep -E '\$WAYBAR_HOME/scripts/[A-Za-z0-9_-]+\.(sh|py)\b' "$file" >/dev/null 2>&1; then
    printf 'FAIL %s has flat scripts/<file> path (need scripts/<domain>/…)\n' "$file" >&2
    grep -nE '\$WAYBAR_HOME/scripts/[A-Za-z0-9_-]+\.(sh|py)\b' "$file" >&2 || true
    fail=1
  fi
done

# Resolve $WAYBAR_HOME / $HOME script refs and ensure targets exist (catches migration misses).
if ! python3 - "$WAYBAR_HOME" <<'PY'
import os, re, sys
from pathlib import Path

home = Path(sys.argv[1]).resolve()
roots = [
    home / "modules",
    home / "includes",
    home / "layouts",
    home / "config.jsonc",
]
pat = re.compile(
    r"\$(?:WAYBAR_HOME|HOME)/scripts/[A-Za-z0-9_./+-]+\.(?:sh|py)"
)
# Also match unquoted concatenations like $WAYBAR_HOME/scripts/foo in JSON strings
missing = []
checked = set()

def expand(ref: str) -> Path:
    ref = ref.replace("$WAYBAR_HOME", str(home)).replace("$HOME", str(Path.home()))
    return Path(ref)

files = []
for root in roots:
    if root.is_file():
        files.append(root)
    elif root.is_dir():
        files.extend(sorted(root.glob("*.jsonc")))
        files.extend(sorted(root.glob("*.generated.jsonc")))

for path in files:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"FAIL cannot read {path}: {exc}", file=sys.stderr)
        sys.exit(1)
    for m in pat.finditer(text):
        ref = m.group(0)
        if ref in checked:
            continue
        checked.add(ref)
        target = expand(ref)
        if not target.is_file():
            missing.append((str(path), ref, str(target)))

if missing:
    for src, ref, target in missing:
        print(f"FAIL missing script for {ref} (from {src}) -> {target}", file=sys.stderr)
    sys.exit(1)
print(f"ok resolved {len(checked)} script path refs under {home}")
sys.exit(0)
PY
then
  fail=1
fi

# Contract checks
settings="$WAYBAR_HOME/data/waybar-settings.json"
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  if jq -e 'has("poll_intervals")' "$settings" >/dev/null 2>&1; then
    printf 'FAIL %s still has poll_intervals (use module_intervals only)\n' "$settings" >&2
    fail=1
  fi
  if jq -e '.services.i2pd.console_pass != null and (.services.i2pd.console_pass|type) == "string" and (.services.i2pd.console_pass|length) > 0' "$settings" >/dev/null 2>&1; then
    printf 'FAIL %s contains services.i2pd.console_pass — move to data/waybar-secrets.jsonc\n' "$settings" >&2
    fail=1
  fi
  if [ ! -f "$WAYBAR_HOME/modules/workspaces.generated.jsonc" ]; then
    printf 'FAIL missing modules/workspaces.generated.jsonc\n' >&2
    fail=1
  fi
  if ! jq -e '.bars.layer == "overlay" and .bars.tooltip == true' "$settings" >/dev/null 2>&1; then
    printf 'WARN %s: expected bars.layer=overlay and tooltip=true for KWin tooltips\n' "$settings" >&2
  fi
fi

secrets_file="$WAYBAR_HOME/data/waybar-secrets.jsonc"
if [ -f "$secrets_file" ]; then
  mode=$(stat -c '%a' "$secrets_file" 2>/dev/null || stat -f '%OLp' "$secrets_file" 2>/dev/null || echo '')
  if [ -n "$mode" ] && [ "$mode" != "600" ] && [ "$mode" != "0600" ]; then
    printf 'FAIL %s mode is %s (expected 600)\n' "$secrets_file" "$mode" >&2
    fail=1
  fi
fi

exit "$fail"
