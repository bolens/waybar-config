#!/usr/bin/env bash
# icons.appicon CSS generator contracts (dock PNG proof via appicon CLI).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "dock-appicon-css"
waybar_test_gen_sandbox

css="$TEST_DIR/theme/dock-appicons.generated.css"
semantic="$TEST_DIR/theme/semantic-colors.generated.css"

waybar_test_patch_settings '.icons.appicon.enabled = false'
if ! waybar_test_gen_default; then
  echo "FAIL: generate failed before dock-appicon checks" >&2
  exit 1
fi
if [ ! -f "$css" ]; then
  echo "FAIL: dock-appicons.generated.css missing when icons.appicon disabled" >&2
  exit 1
fi
if ! grep -q 'icons.appicon disabled' "$css"; then
  echo "FAIL: disabled dock-appicons.generated.css should be a stub" >&2
  exit 1
fi

waybar_test_patch_settings \
  '.icons.appicon.enabled = true | .icons.appicon.size = 28 | .icons.appicon.gap = 12 | .icons.appicon.pad = 8'
if ! waybar_test_gen_default; then
  echo "FAIL: generate failed with icons.appicon enabled" >&2
  exit 1
fi
if [ ! -f "$css" ]; then
  echo "FAIL: dock-appicons.generated.css missing when icons.appicon enabled" >&2
  exit 1
fi
if ! grep -q 'min-width: 28px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should use icons.appicon.size" >&2
  exit 1
fi
if ! grep -q 'background-size: 28px 28px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should set exact background-size" >&2
  exit 1
fi
if ! grep -q 'margin-right: 12px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should use icons.appicon.gap" >&2
  exit 1
fi
if ! grep -q 'padding: 8px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should use icons.appicon.pad on all sides" >&2
  exit 1
fi
# Layout must apply without .appicon so glyph fallbacks keep the same gaps.
if ! grep -qE '^#custom-dock-[a-z0-9-]+,' "$css"; then
  echo "FAIL: expected shared #custom-dock-* layout rules without requiring .appicon" >&2
  exit 1
fi
if ! grep -qE 'url\("file://.*/theme/dock-appicons/browser\.png"\)' "$css"; then
  echo "FAIL: expected file://…/theme/dock-appicons/browser.png CSS rule (stable across style reload)" >&2
  exit 1
fi
# Regression: relative urls break after reload_style_on_change — icons vanish until restart.
if grep -E 'url\("dock-appicons/|url\("theme/dock-appicons/' "$css"; then
  echo "FAIL: dock-appicons.generated.css must use file:// urls, not relative theme/dock-appicons/" >&2
  exit 1
fi
if grep -E 'url\("dock-win-icons/|url\("theme/dock-win-icons/' "$css"; then
  echo "FAIL: dock-appicons.generated.css must not use relative dock-win-icons/ urls" >&2
  exit 1
fi
# Every background-image for PNGs must be absolute file:// under WAYBAR_HOME/theme/.
while IFS= read -r u; do
  [ -n "$u" ] || continue
  case "$u" in
    file://*/theme/dock-appicons/* | file://*/theme/dock-win-icons/*) ;;
    *)
      echo "FAIL: dock appicon CSS url must be file://…/theme/dock-*-icons/… (got: $u)" >&2
      exit 1
      ;;
  esac
done < <(grep -oE 'url\("[^"]+\.png"\)' "$css" | sed -E 's/^url\("//; s/"\)$//' || true)
# Generators must emit file:// (catch source drift before regen).
if ! grep -Fq 'waybar_appicon_css_file_url' "$ROOT_DIR/scripts/generate/generate-dock-appicon-css.sh"; then
  echo "FAIL: generate-dock-appicon-css.sh must use waybar_appicon_css_file_url" >&2
  exit 1
fi
if grep -nE "printf ['\"]theme/dock-appicons/|printf ['\"]dock-appicons/" "$ROOT_DIR/scripts/generate/generate-dock-appicon-css.sh"; then
  echo "FAIL: generate-dock-appicon-css.sh still formats relative dock-appicons urls" >&2
  exit 1
fi
if ! grep -q '#custom-dock-browser.appicon:hover' "$css"; then
  echo "FAIL: expected hover rules that keep background-image" >&2
  exit 1
fi
if ! grep -q ':not(\.appicon)' "$ROOT_DIR/theme/accents/dock.css"; then
  echo "FAIL: accents/dock.css must skip .appicon for glyph color/hover" >&2
  exit 1
fi

# Pill hover must use background-color (not background shorthand) or icons vanish.
if [ -f "$semantic" ]; then
  if grep -E '^[[:space:]]*background:' "$semantic" | grep -q '0\.12\|pill'; then
    :
  fi
  if ! grep -q 'background-color:' "$semantic"; then
    echo "FAIL: semantic-colors.generated.css must use background-color for pills" >&2
    exit 1
  fi
  # The hover block should not use background shorthand next to box-shadow pill glow.
  hover_block="$(tr '\n' ' ' <"$semantic" | grep -oE '\{[^}]*box-shadow: 0 0 10px[^}]*\}' | head -1 || true)"
  if printf '%s' "$hover_block" | grep -qE '[[:space:]]background:'; then
    echo "FAIL: pill hover must not use background shorthand (wipes background-image)" >&2
    exit 1
  fi
fi

theme_css="$ROOT_DIR/theme.css"
sem_line="$(grep -n 'semantic-colors.generated.css' "$theme_css" | head -1 | cut -d: -f1)"
icon_line="$(grep -n 'dock-appicons.generated.css' "$theme_css" | head -1 | cut -d: -f1)"
dock_win_line="$(grep -n 'dock-windows.generated.css' "$theme_css" | head -1 | cut -d: -f1)"
if [ -z "$sem_line" ] || [ -z "$icon_line" ] || [ "$icon_line" -le "$sem_line" ]; then
  echo "FAIL: theme.css must import dock-appicons.generated.css after semantic-colors" >&2
  exit 1
fi
if [ -z "$dock_win_line" ] || [ "$dock_win_line" -le "$sem_line" ]; then
  echo "FAIL: theme.css must import dock-windows.generated.css after semantic-colors" >&2
  exit 1
fi

# dock-windows slot PNGs share icons.appicon via appicon-<dock-apps-id>
win_css="$TEST_DIR/theme/dock-windows.generated.css"
if ! grep -q 'appicon-browser' "$win_css"; then
  echo "FAIL: expected appicon-browser CSS when icons.appicon.enabled" >&2
  exit 1
fi
if ! grep -qE 'url\("file://.*/theme/dock-appicons/browser\.png"\)' "$win_css"; then
  echo "FAIL: expected dock-windows CSS file://…/theme/dock-appicons/browser.png" >&2
  exit 1
fi
if grep -E 'url\("dock-appicons/|url\("theme/dock-appicons/|url\("dock-win-icons/|url\("theme/dock-win-icons/' "$win_css"; then
  echo "FAIL: dock-windows.generated.css must use file:// urls, not relative dock-*-icons/" >&2
  exit 1
fi
if ! grep -Fq 'waybar_appicon_css_file_url' "$ROOT_DIR/scripts/generate/generate-dock-windows-css.sh"; then
  echo "FAIL: generate-dock-windows-css.sh must use waybar_appicon_css_file_url" >&2
  exit 1
fi
if ! grep -Fq 'waybar_appicon_css_file_url' "$ROOT_DIR/scripts/dock/dock-windows-slot-status.sh"; then
  echo "FAIL: dock-windows-slot-status.sh runtime CSS must use waybar_appicon_css_file_url" >&2
  exit 1
fi
if ! grep -Fq 'waybar_appicon_emit_text' "$ROOT_DIR/scripts/dock/dock-launcher.sh"; then
  echo "FAIL: dock-launcher must use waybar_appicon_emit_text (glyph hitbox for tooltips)" >&2
  exit 1
fi
if ! grep -Fq 'waybar_appicon_emit_text' "$ROOT_DIR/scripts/dock/dock-windows-slot-status.sh"; then
  echo "FAIL: dock-windows-slot-status must use waybar_appicon_emit_text" >&2
  exit 1
fi
# Anti-pattern: empty text + .appicon vanishes after CSS hot-reload until waybar restart.
if grep -nE 'emit_text=""' "$ROOT_DIR/scripts/dock/dock-launcher.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-slot-status.sh"; then
  echo "FAIL: dock status scripts must not clear emit_text to empty with .appicon" >&2
  exit 1
fi
# Anti-pattern: font-size:0 collapses GtkLabel → Plasma tooltips stop working.
if grep -nE 'font-size: 0' "$ROOT_DIR/scripts/generate/generate-dock-appicon-css.sh" \
  "$ROOT_DIR/scripts/generate/generate-dock-windows-css.sh" \
  "$ROOT_DIR/scripts/lib/dock-windows-kde-lib.sh"; then
  echo "FAIL: dock appicon CSS must not set font-size:0 (breaks Plasma tooltips)" >&2
  exit 1
fi
if grep -nE 'font-size: 0' "$css" "$win_css"; then
  echo "FAIL: generated dock appicon CSS must not set font-size:0" >&2
  exit 1
fi
# Plasma tooltip hitbox: .appicon must hide paint via color, keep metrics + box size.
if ! awk '
  /#custom-dock-browser\.appicon,/ { inblock=1; next }
  inblock && /color: transparent/ { found_c=1 }
  inblock && /font-size: 0/ { bad_fs=1 }
  inblock && /padding:/ { found_pad=1 }
  inblock && /^}/ {
    exit (found_c && found_pad && !bad_fs) ? 0 : 1
  }
' "$css"; then
  echo "FAIL: #custom-dock-browser.appicon must use color:transparent + padding, without font-size:0" >&2
  exit 1
fi
# Shared layout min-width (even without .appicon) keeps a hover target.
if ! grep -qE 'min-width: [0-9]+px' "$css"; then
  echo "FAIL: dock-appicons CSS must set min-width for launcher hitbox" >&2
  exit 1
fi
# Bottom-bar tooltip placement: vertical margins push popups off-screen (Waybar#3356).
if grep -nE 'margin-top: [1-9]|margin-bottom: [1-9]' "$css"; then
  echo "FAIL: dock-appicons CSS must not use vertical margins (breaks bottom tooltips)" >&2
  exit 1
fi
if ! grep -qE 'color: transparent' "$css"; then
  echo "FAIL: dock-appicons.generated.css must hide glyph paint with color:transparent" >&2
  exit 1
fi
echo "PASS: Plasma tooltip hitbox CSS contract (no font-size:0; color:transparent)"
if ! grep -qE '#custom-dock-browser\.appicon label' "$css"; then
  echo "FAIL: dock-appicons CSS must expand GtkLabel hitbox (.appicon label)" >&2
  exit 1
fi
if ! grep -Fq '"format": "{text}"' "$ROOT_DIR/scripts/generate/generate-dock-modules.sh"; then
  echo "FAIL: dock modules must use format {text} (Waybar binds tooltips to GtkLabel)" >&2
  exit 1
fi
if ! grep -Fq 'format: "{text}"' "$ROOT_DIR/scripts/generate/generate-active-window-modules.sh"; then
  echo "FAIL: active-window must use format {text}" >&2
  exit 1
fi
if ! grep -Fq 'hide-empty-text' "$ROOT_DIR/scripts/generate/generate-dock-modules.sh"; then
  echo "FAIL: generate-dock-modules.sh must set hide-empty-text false" >&2
  exit 1
fi
# Generated module JSON must keep dock launchers visible when placeholder/CSS race.
dock_mods="$TEST_DIR/modules/dock.generated.jsonc"
if [ ! -f "$dock_mods" ]; then
  echo "FAIL: dock.generated.jsonc missing after generate" >&2
  exit 1
fi
if ! jq -e '
  to_entries
  | map(select(.key | startswith("custom/dock-")))
  | length > 0
  and all(.[]; .value["hide-empty-text"] == false)
' "$dock_mods" >/dev/null; then
  echo "FAIL: every custom/dock-* module must set hide-empty-text=false (got $(
    jq -c '[to_entries[] | select(.key|startswith("custom/dock-")) | {(.key): .value["hide-empty-text"]}]' "$dock_mods" 2>/dev/null
  ))" >&2
  exit 1
fi
if ! jq -e '
  to_entries
  | map(select(.key | startswith("custom/dock-")))
  | length > 0
  and all(.[]; .value.tooltip == true)
' "$dock_mods" >/dev/null; then
  echo "FAIL: every custom/dock-* module must set tooltip=true" >&2
  exit 1
fi
echo "PASS: dock modules enable tooltip=true and hide-empty-text=false"
# Lib contracts used by generators + status scripts.
# shellcheck source=../../../lib/appicon-lib.sh
. "$ROOT_DIR/scripts/lib/appicon-lib.sh"
zwsp="$(waybar_appicon_placeholder_text)"
if [ "${#zwsp}" -ne 1 ] || [ "$zwsp" != $'\u200b' ]; then
  echo "FAIL: waybar_appicon_placeholder_text must be U+200B (got len=${#zwsp})" >&2
  exit 1
fi
if [ "$(waybar_appicon_emit_text '󰈹')" != '󰈹' ]; then
  echo "FAIL: waybar_appicon_emit_text should prefer the real glyph" >&2
  exit 1
fi
if [ "$(waybar_appicon_emit_text '')" != "$zwsp" ]; then
  echo "FAIL: waybar_appicon_emit_text should fall back to ZWSP when icon empty" >&2
  exit 1
fi
file_url="$(WAYBAR_HOME=/tmp/waybar-home waybar_appicon_css_file_url 'theme/dock-appicons/browser.png')"
case "$file_url" in
  file:///tmp/waybar-home/theme/dock-appicons/browser.png) ;;
  *)
    echo "FAIL: waybar_appicon_css_file_url shape (got: $file_url)" >&2
    exit 1
    ;;
esac
if grep -q 'dock-win-icons/slot-0' "$win_css"; then
  echo "FAIL: dock-windows must not use per-slot PNG URLs (multi-output race)" >&2
  exit 1
fi
# Glyph paint guard: generic .appicon hides paint (not font metrics) for tooltip hitbox.
if ! grep -Fq 'Hide glyph paint whenever .appicon is set' "$win_css"; then
  echo "FAIL: dock-windows CSS must include generic .appicon glyph-hide rule" >&2
  exit 1
fi
if ! awk '
  /Hide glyph paint whenever \.appicon is set/ { inblock=1; next }
  inblock && /color: transparent/ { found_c=1 }
  inblock && /font-size: 0/ { bad_fs=1 }
  inblock && /^}/ { exit (found_c && !bad_fs) ? 0 : 1 }
' "$win_css"; then
  echo "FAIL: generic .appicon rule must set color:transparent and must NOT set font-size:0" >&2
  exit 1
fi
if ! grep -q ':not(\.appicon)' "$TEST_DIR/theme/semantic-colors.generated.css"; then
  echo "FAIL: semantic dock-win color rules must skip .appicon" >&2
  exit 1
fi
if ! git -C "$ROOT_DIR" check-ignore -q --no-index theme/dock-win-icons/browser.png; then
  echo "FAIL: theme/dock-win-icons/*.png must be gitignored" >&2
  exit 1
fi

if [ ! -x "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" ]; then
  echo "FAIL: dock-appicon-prefetch.sh missing or not executable" >&2
  exit 1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" \
  "dock-appicon-prefetch.sh failed bash -n"
if [ ! -f "$TEST_DIR/scripts/lib/appicon-lib.sh" ]; then
  echo "FAIL: appicon-lib.sh missing" >&2
  exit 1
fi

if git -C "$ROOT_DIR" check-ignore -q --no-index theme/dock-appicons.generated.css; then
  echo "FAIL: theme/dock-appicons.generated.css must NOT be gitignored" >&2
  exit 1
fi
if ! git -C "$ROOT_DIR" check-ignore -q --no-index theme/dock-appicons/browser.png; then
  echo "FAIL: theme/dock-appicons/*.png must be gitignored" >&2
  exit 1
fi

if [ ! -x "$TEST_DIR/scripts/infra/install-appicon.sh" ]; then
  echo "FAIL: install-appicon.sh missing or not executable" >&2
  exit 1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/infra/install-appicon.sh" \
  "install-appicon.sh failed bash -n"

waybar_test_end
