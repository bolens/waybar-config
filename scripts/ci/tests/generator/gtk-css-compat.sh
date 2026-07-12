#!/usr/bin/env bash
# Regression: GTK3/Waybar CSS must not use properties or keyframe forms that crash Waybar.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "gtk-css-compat"
waybar_test_gen_sandbox

echo "Testing generate emits GTK3-safe animations keyframes..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before gtk-css-compat checks" >&2
  fail=1
fi

anim="$TEST_DIR/theme/animations.generated.css"
if [ ! -f "$anim" ]; then
  echo "FAIL: animations.generated.css missing after generate" >&2
  fail=1
fi

# Must use from/to (or single %), never "0%, 100%" style multi-selectors.
if grep -E '^[[:space:]]*[0-9]+%[[:space:]]*,[[:space:]]*[0-9]+%' "$anim"; then
  echo "FAIL: animations.generated.css has multi-percentage keyframe selectors (crashes Waybar)" >&2
  fail=1
fi
if ! grep -qE '^[[:space:]]*(from|to)[[:space:]]*\{' "$anim"; then
  echo "FAIL: expected from/to keyframes in animations.generated.css when animations enabled" >&2
  fail=1
fi

echo "Testing repo CSS via check-gtk-css.sh..."
if ! bash "$ROOT_DIR/scripts/ci/check-gtk-css.sh" "$ROOT_DIR"; then
  echo "FAIL: check-gtk-css.sh reported unsafe CSS in repo" >&2
  fail=1
fi

echo "Testing sandbox CSS after generate..."
mapfile -t sandbox_css < <(find "$TEST_DIR" -type f -name '*.css' ! -path '*/theme/rofi/*' | sort)
# Keep in sync with scripts/ci/check-gtk-css.sh disallowed_props.
unsafe_props=(
  font-variant-ligatures font-variant-numeric font-feature-settings
  backdrop-filter filter transform
  width height max-width max-height
  overflow overflow-x overflow-y text-overflow
  display flex gap position z-index
  line-height white-space text-align
  box-sizing cursor
)
for prop in "${unsafe_props[@]}"; do
  if grep -nE "^[[:space:]]*${prop}[[:space:]]*:" "${sandbox_css[@]}" 2>/dev/null; then
    echo "FAIL: sandbox CSS contains unsafe property ${prop}" >&2
    fail=1
  fi
done
if grep -nE '^[[:space:]]*[0-9]+%[[:space:]]*,[[:space:]]*[0-9]+%' "${sandbox_css[@]}" 2>/dev/null; then
  echo "FAIL: sandbox CSS has multi-percentage keyframe selectors" >&2
  fail=1
fi

echo "Testing fit_content workspace CSS never emits GTK3-unsafe sizing/overflow..."
ws_gen="$TEST_DIR/theme/workspaces.generated.css"
if [ -f "$ws_gen" ] && grep -nE '^[[:space:]]*(width|height|max-width|max-height|overflow|overflow-x|overflow-y)[[:space:]]*:' "$ws_gen"; then
  echo "FAIL: workspaces.generated.css emits GTK3-unsafe sizing/overflow props" >&2
  fail=1
fi

echo "Testing scanner catches known-bad fixture tree..."
bad_root=$(mktemp -d)
mkdir -p "$bad_root/theme"
cat >"$bad_root/theme/bad-gtk-fixture.css" <<'EOF'
#custom-cava {
    font-variant-ligatures: none;
    display: flex;
    gap: 4px;
    cursor: pointer;
}
#custom-ws-0.hidden {
    width: 0;
    max-width: 0;
    overflow: hidden;
    line-height: 1;
}
@keyframes boom {
    0%, 100% {
        opacity: 1;
    }
}
EOF
if bash "$ROOT_DIR/scripts/ci/check-gtk-css.sh" "$bad_root" >/dev/null 2>&1; then
  echo "FAIL: check-gtk-css.sh should reject expanded GTK3-unsafe props + multi-% keyframes" >&2
  fail=1
fi
rm -rf "$bad_root"

echo "Testing scanner rejects :root / var() / custom properties..."
modern_root=$(mktemp -d)
mkdir -p "$modern_root/theme"
cat >"$modern_root/theme/modern-css-fixture.css" <<'EOF'
:root {
    --wb-text: #e0e0e0;
}
#workspaces button {
    color: var(--wb-text);
}
EOF
if bash "$ROOT_DIR/scripts/ci/check-gtk-css.sh" "$modern_root" >/dev/null 2>&1; then
  echo "FAIL: check-gtk-css.sh should reject :root / var() / custom properties" >&2
  fail=1
else
  echo "PASS: :root / var() rejected"
fi
rm -rf "$modern_root"

echo "Testing comment mentions of :root do not false-positive..."
ok_root=$(mktemp -d)
mkdir -p "$ok_root/theme"
cat >"$ok_root/theme/comment-ok.css" <<'EOF'
/* Docs: do not use :root or var(--x) — bake colors. */
#waybar {
    color: #e0e0e0;
}
EOF
if ! bash "$ROOT_DIR/scripts/ci/check-gtk-css.sh" "$ok_root" >/dev/null 2>&1; then
  echo "FAIL: check-gtk-css.sh should allow comments that mention :root / var()" >&2
  fail=1
else
  echo "PASS: comments mentioning :root are ignored"
fi
rm -rf "$ok_root"

echo "Testing sandbox CSS has no :root / var() after generate..."
if ! python3 - "$TEST_DIR" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
bad = []
for path in root.rglob("*.css"):
    if "rofi" in path.parts:
        continue
    text = re.sub(r"/\*.*?\*/", "", path.read_text(errors="ignore"), flags=re.S)
    if re.search(r"(^|[\s,}])(:root)(\s*[,{])", text, re.M) or re.search(r"\bvar\s*\(", text):
        bad.append(str(path.relative_to(root)))
if bad:
    print("\n".join(bad))
    sys.exit(1)
PY
then
  echo "FAIL: sandbox CSS still contains :root or var()" >&2
  fail=1
else
  echo "PASS: sandbox CSS free of :root / var()"
fi

if [ -x "$ROOT_DIR/scripts/ci/waybar-gtk-css-smoke.sh" ] && { [ -f "$TEST_DIR/theme.css" ] || [ -f "$TEST_DIR/style.css" ]; }; then
  if ! bash "$ROOT_DIR/scripts/ci/waybar-gtk-css-smoke.sh" "$TEST_DIR"; then
    echo "FAIL: waybar-gtk-css-smoke.sh rejected sandbox CSS" >&2
    fail=1
  fi
fi

echo "Testing allowlist rejects unknown property names..."
unk_root=$(mktemp -d)
mkdir -p "$unk_root/theme"
cat >"$unk_root/theme/unknown-prop.css" <<'EOF'
#probe {
    totally-fake-property: 1;
}
EOF
if bash "$ROOT_DIR/scripts/ci/check-gtk-css.sh" "$unk_root" >/dev/null 2>&1; then
  echo "FAIL: check-gtk-css.sh should reject properties absent from GTK3 allowlist" >&2
  fail=1
else
  echo "PASS: allowlist rejects unknown property names"
fi
rm -rf "$unk_root"

if [ ! -f "$ROOT_DIR/scripts/ci/lib/gtk3-css-property-allowlist.txt" ]; then
  echo "FAIL: missing scripts/ci/lib/gtk3-css-property-allowlist.txt" >&2
  fail=1
fi

echo "PASS: gtk-css-compat"
waybar_test_end
