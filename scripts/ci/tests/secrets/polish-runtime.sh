#!/usr/bin/env bash
# Polish runtime settings wiring (updates/github/rofi/etc).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "polish-runtime"
waybar_test_secrets_sandbox
waybar_test_secrets_copy_polish_scripts
waybar_test_install_path_stubs
waybar_test_install_script_stubs
waybar_test_compile_settings

# updates-status: settings enable_aur=true should invoke paru
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! grep -q '^paru$' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: updates-status should call paru when updates.enable_aur=true. log=$(cat "$TEST_DIR/bin/calls.log") out=$out" >&2
  fail=1
fi
waybar_test_assert_jq "$out" '.tooltip | test("AUR updates: 1")' "updates-status tooltip missing AUR count. out=$out"

# env override WAYBAR_UPDATES_ENABLE_AUR=0 disables even when settings true
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
    WAYBAR_UPDATES_ENABLE_AUR=0 \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if grep -q '^paru$' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: WAYBAR_UPDATES_ENABLE_AUR=0 should skip paru" >&2
  fail=1
fi
waybar_test_assert_jq "$out" '.tooltip | test("AUR updates: 0")' "AUR disabled should report 0. out=$out"

# Cross-distro backends (no paru required)
waybar_test_install_path_stub_extras apt dnf
chmod +x "$TEST_DIR/bin/flatpak"
rm -f "$TEST_DIR/bin/checkupdates" # force non-arch if backend not overridden
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
    WAYBAR_UPDATES_BACKEND=apt \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$out" '.tooltip | test("Backend: apt") and test("APT updates: 1")' "updates-status apt backend. out=$out"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
    WAYBAR_UPDATES_BACKEND=dnf \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$out" '.tooltip | test("Backend: dnf") and test("DNF updates: 1")' "updates-status dnf backend. out=$out"
# Restore Arch stubs for remaining tests
cp "$(waybar_test_lib_dir)/fixtures/bin-stubs/checkupdates" "$TEST_DIR/bin/checkupdates"
chmod +x "$TEST_DIR/bin/checkupdates"

# updates-review without paru: apt_update settings path
python3 - "$TEST_DIR/data/waybar-settings.jsonc" <<'PY'
import json, re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
data = json.loads(text)
data.setdefault("apps", {})["apt_update"] = "MOCK_APT_UP"
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2) + "\n")
PY
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)
waybar_test_write_bin_stub apt <<'EOF'
#!/usr/bin/env sh
printf 'pkg/stable 1.0 [upgradable from: 0.9]\n'
EOF
# Default polish rofi stub returns Close for System Updates — force Upgrade pick
waybar_test_write_bin_stub rofi <<'EOF'
#!/usr/bin/env sh
printf 'rofi %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
printf '🚀 Upgrade System Now\n'
EOF
rm -f "$TEST_DIR/bin/paru"
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" WAYBAR_UPDATES_BACKEND=apt \
  "$TEST_DIR/scripts/services/sync/updates-review.sh" >/dev/null 2>&1 || true
if ! grep -q 'app-open MOCK_APT_UP' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: updates-review without paru should use apps.apt_update. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi
# Restore paru + default rofi stubs
cat >"$TEST_DIR/bin/paru" <<'EOF'
#!/usr/bin/env sh
printf 'paru\n' >>"${WAYBAR_HOME}/bin/calls.log"
printf 'aur/pkg 1-1 -> 1-2\n'
EOF
cat >"$TEST_DIR/bin/rofi" <<'EOF'
#!/usr/bin/env sh
printf 'rofi %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
# echo first menu line for click scripts that expect a selection
if printf '%s' "$*" | grep -q 'Power Profile'; then
  printf '⚡ performance\n'
elif printf '%s' "$*" | grep -q 'System Updates'; then
  printf '❌ Close\n'
elif printf '%s' "$*" | grep -q 'Select Device'; then
  printf 'Phone\n'
elif printf '%s' "$*" | grep -q 'Action'; then
  printf 'Ping\n'
elif printf '%s' "$*" | grep -q 'Device Notifier'; then
  printf '󰑐 Rescan Devices\n'
elif printf '%s' "$*" | grep -q 'KDE Vaults'; then
  exit 0
else
  cat >/dev/null
  exit 0
fi
EOF
chmod +x "$TEST_DIR/bin/paru" "$TEST_DIR/bin/rofi"

# github-status: preview_limit=3 truncates 5 items
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
    "$TEST_DIR/scripts/services/apps/github-status.sh" --refresh 2>/dev/null | tail -n 1
)
waybar_test_assert_jq "$out" '.tooltip | test("and 2 more")' "github.preview_limit=3 should leave 2 more. out=$out"
# count preview lines with "- [o/" — should be 3
preview_lines=$(echo "$out" | jq -r '.tooltip' | grep -c '^- \[o/' || true)
if [[ "$preview_lines" -ne 3 ]]; then
  echo "FAIL: expected 3 github preview lines, got $preview_lines. out=$out" >&2
  fail=1
fi

# privacy-click right uses apps.privacy_settings / camera_settings
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/services/security/privacy-click.sh" screenshare right
if ! grep -q 'app-open MOCK_PRIVACY' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: privacy screenshare right should open apps.privacy_settings. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/services/security/privacy-click.sh" webcam right
if ! grep -q 'app-open MOCK_CAMERA' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: privacy webcam right should open apps.camera_settings. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# notifications-lib settings app
: >"$TEST_DIR/bin/calls.log"
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/notifications-lib.sh"
  kde_open_settings
)
if ! grep -q 'app-open MOCK_NOTIF' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: kde_open_settings should use apps.notifications_settings. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# keybindhint: hyprkeys gets hypr_tools.keybinds_config; terminal fallback uses apps.terminal
waybar_test_install_path_stub_extras hyprkeys
: >"$TEST_DIR/bin/calls.log"
printf 'bind = SUPER, Q, killactive\n' >"$TEST_DIR/mock-hypr.conf"
# Point settings keybinds_config at TEST_DIR file for hermetic runs
perl -i -pe 's|"keybinds_config": "/tmp/mock-hypr.conf"|"keybinds_config": "'"$TEST_DIR"'/mock-hypr.conf"|' \
  "$TEST_DIR/data/waybar-settings.jsonc"
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)
WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" \
  "$TEST_DIR/scripts/workspaces/keybindhint-click.sh" >/dev/null 2>&1 || true
if ! grep -q "config=${TEST_DIR}/mock-hypr.conf" "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: keybindhint should pass hypr_tools.keybinds_config to hyprkeys. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi
# Terminal fallback when rofi/wofi unavailable
sed -e 's/command -v rofi/false/' -e 's/command -v wofi/false/' \
  "$TEST_DIR/scripts/workspaces/keybindhint-click.sh" >"$TEST_DIR/scripts/keybindhint-click-norofi.sh"
chmod +x "$TEST_DIR/scripts/keybindhint-click-norofi.sh"
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" \
  "$TEST_DIR/scripts/keybindhint-click-norofi.sh" >/dev/null 2>&1 || true
if ! grep -q 'app-open MOCK_TERM -e less' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: keybindhint fallback should use apps.terminal. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# updates-review rofi size from settings
: >"$TEST_DIR/bin/calls.log"
# force some pending updates so menu opens
waybar_test_write_bin_stub checkupdates <<'EOF'
#!/usr/bin/env sh
printf 'pkg 1-1 -> 1-2\n'
EOF
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/services/sync/updates-review.sh" >/dev/null 2>&1 || true
if ! grep -q 'width: 111px' "$TEST_DIR/bin/calls.log" || ! grep -q 'height: 222px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: updates-review should use rofi.updates size. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# powerprofiles rofi size
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/system/powerprofiles-click.sh" menu >/dev/null 2>&1 || true
if ! grep -q 'width: 333px' "$TEST_DIR/bin/calls.log" || ! grep -q 'lines: 4' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: powerprofiles menu should use rofi.powerprofiles size. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# kdeconnect rofi width
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/services/devices/kdeconnect-menu.sh" >/dev/null 2>&1 || true
if ! grep -q 'width: 444px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: kdeconnect-menu should use rofi.kdeconnect.width. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# vaults.py / device-notifier.py rofi widths
mkdir -p "$TEST_DIR/Vaults/TestVault" "$TEST_DIR/Vaults/.TestVault"
touch "$TEST_DIR/Vaults/.TestVault/gocryptfs.conf"
: >"$TEST_DIR/bin/calls.log"
HOME="$TEST_DIR" WAYBAR_HOME="$TEST_DIR" python3 "$TEST_DIR/scripts/services/security/vaults.py" --menu >/dev/null 2>&1 || true
if ! grep -q 'width: 555px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: vaults.py should use rofi.vaults.width. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

: >"$TEST_DIR/bin/calls.log"
waybar_test_install_path_stub_extras lsblk
HOME="$TEST_DIR" WAYBAR_HOME="$TEST_DIR" python3 "$TEST_DIR/scripts/services/devices/device-notifier.py" --menu >/dev/null 2>&1 || true
if ! grep -q 'width: 666px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: device-notifier.py should use rofi.device_notifier.width. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

echo "PASS: polish runtime settings wiring"

waybar_test_end
