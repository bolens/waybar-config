#!/usr/bin/env bash
# Unit tests for secrets overlay, i2pd sync helper, capture/disk settings, and
# validate-generated-config console_pass guard.
set -euo pipefail

echo "=== Running secrets / settings exposure tests ==="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/data" "$TEST_DIR/scripts" "$TEST_DIR/i2pd" "$TEST_DIR/varlib"
cp "$ROOT/scripts/waybar-settings.sh" "$TEST_DIR/scripts/"
cp "$ROOT/scripts/i2pd-set-console-pass.sh" "$TEST_DIR/scripts/"
cp "$ROOT/scripts/capture-lib.sh" "$TEST_DIR/scripts/"
cp "$ROOT/scripts/validate-generated-config.sh" "$TEST_DIR/scripts/"
cp "$ROOT/data/waybar-secrets.example.jsonc" "$TEST_DIR/data/"
chmod +x "$TEST_DIR"/scripts/*.sh

export WAYBAR_HOME="$TEST_DIR"

# Minimal settings (no secrets yet)
cat >"$TEST_DIR/data/waybar-settings.jsonc" <<'JSON'
{
  "capture": {
    "screenshot_dir": "/tmp/wb-shots",
    "screenrecord_dir": "/tmp/wb-recs",
    "screenrecord_fps": 42
  },
  "disk": { "path": "/boot" },
  "updates": { "preview_limit": 7, "enable_aur": true },
  "github": { "preview_limit": 3 },
  "audio": { "seek_back_sec": 15, "seek_forward_sec": 25 },
  "hypr_tools": { "keybinds_config": "/tmp/mock-hypr.conf" },
  "streamdeck": { "service_name": "mock-streamdeck.service" },
  "rofi": {
    "updates": { "width": 111, "height": 222 },
    "powerprofiles": { "width": 333, "lines": 4 },
    "kdeconnect": { "width": 444 },
    "vaults": { "width": 555 },
    "device_notifier": { "width": 666 }
  },
  "thresholds": {
    "updates": { "warning": 3, "critical": 9 },
    "ups": { "charge": { "warning": 40, "critical": 12 } },
    "device_battery": { "warning": 33, "critical": 11 }
  },
  "services": {
    "i2pd": {
      "console_url": "http://127.0.0.1:7070/",
      "console_user": "i2pd"
    }
  },
  "theme": {
    "tooltip_padding": "1px 2px",
    "colors": {
      "tooltip_background": "#111111",
      "tooltip_border": "#222222",
      "foreground": "#abcdef",
      "background": "rgba(1,2,3,0.5)",
      "border": "rgba(4,5,6,0.5)"
    }
  },
  "apps": {
    "file_manager": "TEST_FM",
    "github_notifications": "https://example.test/notifications",
    "github_home": "https://example.test/home",
    "terminal": "MOCK_TERM",
    "privacy_settings": "MOCK_PRIVACY",
    "camera_settings": "MOCK_CAMERA",
    "notifications_settings": "MOCK_NOTIF",
    "solaar": "TEST_SOLAAR",
    "input_settings": "TEST_INPUT",
    "power_settings": "TEST_POWER"
  },
  "module_intervals": {},
  "signals": {},
  "layouts": { "top": { "position": "top" }, "bottom": { "position": "bottom" } },
  "bars": { "layer": "overlay", "tooltip": true }
}
JSON

# --- secrets overlay ---
echo "Testing waybar_settings secrets overlay..."
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
  base=$(waybar_settings_get '.services.i2pd.console_pass' 'MISSING')
  if [[ "$base" != "MISSING" && -n "$base" && "$base" != "null" ]]; then
    echo "FAIL: console_pass should be absent before secrets file" >&2
    exit 1
  fi
)
# write secrets (never echo value in assertions beyond equality checks)
cat >"$TEST_DIR/data/waybar-secrets.jsonc" <<'JSON'
{
  "services": {
    "i2pd": {
      "console_pass": "overlay-secret-pass-AAAA"
    }
  }
}
JSON
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
  got=$(waybar_settings_get '.services.i2pd.console_pass' '')
  if [[ "$got" != "overlay-secret-pass-AAAA" ]]; then
    echo "FAIL: secrets overlay did not win for console_pass" >&2
    exit 1
  fi
  # settings-only keys still resolve
  disk=$(waybar_settings_get '.disk.path' '')
  if [[ "$disk" != "/boot" ]]; then
    echo "FAIL: disk.path not read from settings (got: $disk)" >&2
    exit 1
  fi
  fps=$(waybar_settings_get '.capture.screenrecord_fps' '')
  if [[ "$fps" != "42" ]]; then
    echo "FAIL: capture.screenrecord_fps not read (got: $fps)" >&2
    exit 1
  fi
  enable_aur=$(waybar_settings_get '.updates.enable_aur' '')
  if [[ "$enable_aur" != "true" ]]; then
    echo "FAIL: updates.enable_aur not read (got: $enable_aur)" >&2
    exit 1
  fi
  gh_preview=$(waybar_settings_get '.github.preview_limit' '')
  if [[ "$gh_preview" != "3" ]]; then
    echo "FAIL: github.preview_limit not read (got: $gh_preview)" >&2
    exit 1
  fi
  seek_back=$(waybar_settings_get '.audio.seek_back_sec' '')
  if [[ "$seek_back" != "15" ]]; then
    echo "FAIL: audio.seek_back_sec not read (got: $seek_back)" >&2
    exit 1
  fi
  seek_fwd=$(waybar_settings_get '.audio.seek_forward_sec' '')
  if [[ "$seek_fwd" != "25" ]]; then
    echo "FAIL: audio.seek_forward_sec not read (got: $seek_fwd)" >&2
    exit 1
  fi
  keybinds=$(waybar_settings_get '.hypr_tools.keybinds_config' '')
  if [[ "$keybinds" != "/tmp/mock-hypr.conf" ]]; then
    echo "FAIL: hypr_tools.keybinds_config not read (got: $keybinds)" >&2
    exit 1
  fi
  sd=$(waybar_settings_get '.streamdeck.service_name' '')
  if [[ "$sd" != "mock-streamdeck.service" ]]; then
    echo "FAIL: streamdeck.service_name not read (got: $sd)" >&2
    exit 1
  fi
  ru=$(waybar_settings_get '.rofi.updates.width' '')
  if [[ "$ru" != "111" ]]; then
    echo "FAIL: rofi.updates.width not read (got: $ru)" >&2
    exit 1
  fi
  rh=$(waybar_settings_get '.rofi.updates.height' '')
  if [[ "$rh" != "222" ]]; then
    echo "FAIL: rofi.updates.height not read (got: $rh)" >&2
    exit 1
  fi
  term=$(waybar_settings_get '.apps.terminal' '')
  if [[ "$term" != "MOCK_TERM" ]]; then
    echo "FAIL: apps.terminal not read (got: $term)" >&2
    exit 1
  fi
  priv=$(waybar_settings_get '.apps.privacy_settings' '')
  if [[ "$priv" != "MOCK_PRIVACY" ]]; then
    echo "FAIL: apps.privacy_settings not read (got: $priv)" >&2
    exit 1
  fi
  cam=$(waybar_settings_get '.apps.camera_settings' '')
  if [[ "$cam" != "MOCK_CAMERA" ]]; then
    echo "FAIL: apps.camera_settings not read (got: $cam)" >&2
    exit 1
  fi
  notif=$(waybar_settings_get '.apps.notifications_settings' '')
  if [[ "$notif" != "MOCK_NOTIF" ]]; then
    echo "FAIL: apps.notifications_settings not read (got: $notif)" >&2
    exit 1
  fi
  ghome=$(waybar_settings_get '.apps.github_home' '')
  if [[ "$ghome" != "https://example.test/home" ]]; then
    echo "FAIL: apps.github_home not read (got: $ghome)" >&2
    exit 1
  fi
)
echo "PASS: secrets overlay + settings getters"

# --- capture-lib helpers ---
echo "Testing capture-lib settings helpers..."
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/capture-lib.sh"
  shot=$(capture_screenshot_base_dir)
  rec=$(capture_screenrecord_base_dir)
  fps=$(capture_screenrecord_fps)
  if [[ "$shot" != "/tmp/wb-shots" || "$rec" != "/tmp/wb-recs" || "$fps" != "42" ]]; then
    echo "FAIL: capture-lib helpers wrong: shot=$shot rec=$rec fps=$fps" >&2
    exit 1
  fi
  # env override beats settings for FPS
  export WAYBAR_SCREENREC_FPS=99
  fps2=$(capture_screenrecord_fps)
  if [[ "$fps2" != "99" ]]; then
    echo "FAIL: WAYBAR_SCREENREC_FPS override ignored (got: $fps2)" >&2
    exit 1
  fi
)
echo "PASS: capture-lib helpers"

# --- validate rejects console_pass in compiled settings ---
echo "Testing validate-generated-config console_pass guard..."
mkdir -p "$TEST_DIR/modules" "$TEST_DIR/includes" "$TEST_DIR/layouts"
# minimal generated stubs so validate doesn't fail for missing files
: >"$TEST_DIR/modules/workspaces.generated.jsonc"
echo '{}' >"$TEST_DIR/modules/workspaces.generated.jsonc"
# compile settings then inject forbidden pass into compiled JSON
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
)
jq '.services.i2pd.console_pass = "should-not-be-here"' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate-generated-config should reject console_pass in settings JSON" >&2
  fail=1
else
  echo "PASS: validate rejects console_pass in settings"
fi
# restore clean compiled settings (no pass)
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
)

# --- i2pd-set-console-pass: push secrets → conf ---
echo "Testing i2pd-set-console-pass push (secrets → conf)..."
cat >"$TEST_DIR/i2pd/i2pd.conf" <<'CONF'
[http]
address = 127.0.0.1
port = 7070
auth = false
# user = i2pd
# pass = old
[httpproxy]
password = unrelated-proxy-secret
CONF
ln -sfn "$TEST_DIR/i2pd/i2pd.conf" "$TEST_DIR/varlib/i2pd.conf"

# secrets already present from overlay test
out1=$(
  I2PD_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
  I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
  "$TEST_DIR/scripts/i2pd-set-console-pass.sh" 2>&1
)
if ! grep -q 'updated:' <<<"$out1"; then
  echo "FAIL: expected conf update on first push. Output: $out1" >&2
  fail=1
fi
if ! grep -q 'auth = true' "$TEST_DIR/i2pd/i2pd.conf"; then
  echo "FAIL: auth not enabled in conf after push" >&2
  fail=1
fi
if ! awk '/^\[http\]/{h=1;next} /^\[/{h=0} h && /^pass[[:space:]]*=/{print; exit}' "$TEST_DIR/i2pd/i2pd.conf" \
  | grep -q 'overlay-secret-pass-AAAA'; then
  echo "FAIL: [http] pass not set from secrets" >&2
  fail=1
fi
# httpproxy password must remain untouched
if ! grep -q 'password = unrelated-proxy-secret' "$TEST_DIR/i2pd/i2pd.conf"; then
  echo "FAIL: [httpproxy] password was altered" >&2
  fail=1
fi

out2=$(
  I2PD_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
  I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
  "$TEST_DIR/scripts/i2pd-set-console-pass.sh" 2>&1
)
if ! grep -q 'already up to date' <<<"$out2"; then
  echo "FAIL: second push should be idempotent. Output: $out2" >&2
  fail=1
fi
if grep -q 'updated:' <<<"$out2"; then
  echo "FAIL: second push should not rewrite conf. Output: $out2" >&2
  fail=1
fi
echo "PASS: i2pd push + idempotent re-run"

# --- i2pd-set-console-pass: import conf → secrets ---
echo "Testing i2pd-set-console-pass import (conf → secrets)..."
rm -f "$TEST_DIR/data/waybar-secrets.jsonc"
cat >"$TEST_DIR/i2pd/i2pd.conf" <<'CONF'
[http]
auth = true
user = i2pd
pass = imported-from-conf-BBBB
CONF
ln -sfn "$TEST_DIR/i2pd/i2pd.conf" "$TEST_DIR/varlib/i2pd.conf"

out3=$(
  I2PD_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
  I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
  "$TEST_DIR/scripts/i2pd-set-console-pass.sh" 2>&1
)
if [[ ! -f "$TEST_DIR/data/waybar-secrets.jsonc" ]]; then
  echo "FAIL: secrets file not created on import. Output: $out3" >&2
  fail=1
fi
if ! grep -q 'imported console_pass\|unchanged (already matches)' <<<"$out3"; then
  echo "FAIL: expected import message. Output: $out3" >&2
  fail=1
fi
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
  got=$(waybar_settings_get '.services.i2pd.console_pass' '')
  if [[ "$got" != "imported-from-conf-BBBB" ]]; then
    echo "FAIL: imported secrets pass mismatch" >&2
    exit 1
  fi
)

out4=$(
  I2PD_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
  I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
  "$TEST_DIR/scripts/i2pd-set-console-pass.sh" 2>&1
)
if ! grep -q 'already up to date' <<<"$out4"; then
  echo "FAIL: import path should be idempotent on re-run. Output: $out4" >&2
  fail=1
fi
echo "PASS: i2pd import + idempotent re-run"

# --- symlink repair (divergent regular file) ---
echo "Testing i2pd var conf symlink repair..."
rm -f "$TEST_DIR/varlib/i2pd.conf"
echo 'not-a-real-conf' >"$TEST_DIR/varlib/i2pd.conf"
out5=$(
  I2PD_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
  I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
  "$TEST_DIR/scripts/i2pd-set-console-pass.sh" 2>&1
)
if [[ ! -L "$TEST_DIR/varlib/i2pd.conf" ]]; then
  echo "FAIL: var conf should become symlink. Output: $out5" >&2
  fail=1
fi
if [[ ! -f "$TEST_DIR/varlib/i2pd.conf.bak" ]]; then
  echo "FAIL: divergent file should be backed up to .bak" >&2
  fail=1
fi
echo "PASS: symlink repair"

# --- polish runtime script wiring ---
echo "Testing polish runtime settings wiring..."
for s in \
  updates-status.sh github-status.sh privacy-click.sh notifications-lib.sh \
  keybindhint-click.sh updates-review.sh powerprofiles-click.sh kdeconnect-menu.sh \
  waybar-cache-helpers.sh unicode-animations-lib.sh compositor-session.sh
do
  cp "$ROOT/scripts/$s" "$TEST_DIR/scripts/"
done
cp "$ROOT/scripts/vaults.py" "$TEST_DIR/scripts/"
cp "$ROOT/scripts/device-notifier.py" "$TEST_DIR/scripts/"
chmod +x "$TEST_DIR"/scripts/*.sh "$TEST_DIR"/scripts/*.py

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/cache"
export XDG_CACHE_HOME="$TEST_DIR/cache"
export PATH="$TEST_DIR/bin:$PATH"

# Shared log for mocked tools
: >"$TEST_DIR/bin/calls.log"

cat >"$TEST_DIR/bin/paru" <<'EOF'
#!/usr/bin/env sh
printf 'paru\n' >>"${WAYBAR_HOME}/bin/calls.log"
printf 'aur/pkg 1-1 -> 1-2\n'
EOF
cat >"$TEST_DIR/bin/checkupdates" <<'EOF'
#!/usr/bin/env sh
printf 'checkupdates\n' >>"${WAYBAR_HOME}/bin/calls.log"
exit 0
EOF
cat >"$TEST_DIR/bin/flatpak" <<'EOF'
#!/usr/bin/env sh
printf 'flatpak\n' >>"${WAYBAR_HOME}/bin/calls.log"
exit 0
EOF
cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env sh
printf 'gh\n' >>"${WAYBAR_HOME}/bin/calls.log"
# five fake notifications
python3 -c 'import json; print(json.dumps([
  {"repository":{"full_name":"o/r1"},"subject":{"title":"t1"},"reason":"mention"},
  {"repository":{"full_name":"o/r2"},"subject":{"title":"t2"},"reason":"mention"},
  {"repository":{"full_name":"o/r3"},"subject":{"title":"t3"},"reason":"mention"},
  {"repository":{"full_name":"o/r4"},"subject":{"title":"t4"},"reason":"mention"},
  {"repository":{"full_name":"o/r5"},"subject":{"title":"t5"},"reason":"mention"}
]))'
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
cat >"$TEST_DIR/bin/notify-send" <<'EOF'
#!/usr/bin/env sh
printf 'notify-send %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
EOF
cat >"$TEST_DIR/bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env sh
printf 'powerprofilesctl %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
case "${1:-}" in
  get) printf 'balanced\n' ;;
  set) ;;
esac
EOF
cat >"$TEST_DIR/bin/kdeconnect-cli" <<'EOF'
#!/usr/bin/env sh
printf 'kdeconnect-cli %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
if printf '%s' "$*" | grep -q -- '-a'; then
  printf 'dev1 Phone\n'
fi
EOF
cat >"$TEST_DIR/bin/hyprctl" <<'EOF'
#!/usr/bin/env sh
printf 'bind = SUPER, Q, killactive\n'
EOF
cat >"$TEST_DIR/bin/timeout" <<'EOF'
#!/usr/bin/env sh
# ignore duration arg and run the rest
shift
exec "$@"
EOF
chmod +x "$TEST_DIR"/bin/*

# Stub app-open + compositor-gate for privacy/keybindhint
cat >"$TEST_DIR/scripts/app-open.sh" <<'EOF'
#!/usr/bin/env sh
printf 'app-open %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
EOF
cat >"$TEST_DIR/scripts/compositor-gate.sh" <<'EOF'
#!/usr/bin/env sh
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    *) shift ;;
  esac
done
exec "$@"
EOF
cat >"$TEST_DIR/scripts/waybar-signal.sh" <<'EOF'
#!/usr/bin/env sh
printf 'waybar-signal %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
EOF
chmod +x "$TEST_DIR/scripts/app-open.sh" "$TEST_DIR/scripts/compositor-gate.sh" "$TEST_DIR/scripts/waybar-signal.sh"

# Recompile settings so getters see polish keys
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
)

# updates-status: settings enable_aur=true should invoke paru
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
    "$TEST_DIR/scripts/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! grep -q '^paru$' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: updates-status should call paru when updates.enable_aur=true. log=$(cat "$TEST_DIR/bin/calls.log") out=$out" >&2
  fail=1
fi
if ! echo "$out" | jq -e '.tooltip | test("AUR updates: 1")' >/dev/null 2>&1; then
  echo "FAIL: updates-status tooltip missing AUR count. out=$out" >&2
  fail=1
fi

# env override WAYBAR_UPDATES_ENABLE_AUR=0 disables even when settings true
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
  WAYBAR_UPDATES_ENABLE_AUR=0 \
    "$TEST_DIR/scripts/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if grep -q '^paru$' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: WAYBAR_UPDATES_ENABLE_AUR=0 should skip paru" >&2
  fail=1
fi
if ! echo "$out" | jq -e '.tooltip | test("AUR updates: 0")' >/dev/null 2>&1; then
  echo "FAIL: AUR disabled should report 0. out=$out" >&2
  fail=1
fi

# github-status: preview_limit=3 truncates 5 items
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
    "$TEST_DIR/scripts/github-status.sh" --refresh 2>/dev/null | tail -n 1
)
if ! echo "$out" | jq -e '.tooltip | test("and 2 more")' >/dev/null 2>&1; then
  echo "FAIL: github.preview_limit=3 should leave 2 more. out=$out" >&2
  fail=1
fi
# count preview lines with "- [o/" — should be 3
preview_lines=$(echo "$out" | jq -r '.tooltip' | grep -c '^- \[o/' || true)
if [[ "$preview_lines" -ne 3 ]]; then
  echo "FAIL: expected 3 github preview lines, got $preview_lines. out=$out" >&2
  fail=1
fi

# privacy-click right uses apps.privacy_settings / camera_settings
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/privacy-click.sh" screenshare right
if ! grep -q 'app-open MOCK_PRIVACY' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: privacy screenshare right should open apps.privacy_settings. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/privacy-click.sh" webcam right
if ! grep -q 'app-open MOCK_CAMERA' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: privacy webcam right should open apps.camera_settings. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# notifications-lib settings app
: >"$TEST_DIR/bin/calls.log"
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/notifications-lib.sh"
  kde_open_settings
)
if ! grep -q 'app-open MOCK_NOTIF' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: kde_open_settings should use apps.notifications_settings. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# keybindhint: hyprkeys gets hypr_tools.keybinds_config; terminal fallback uses apps.terminal
cat >"$TEST_DIR/bin/hyprkeys" <<'EOF'
#!/usr/bin/env sh
printf 'hyprkeys %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
while [ $# -gt 0 ]; do
  case "$1" in
    -c)
      printf 'config=%s\n' "$2" >>"${WAYBAR_HOME}/bin/calls.log"
      shift 2
      ;;
    *) shift ;;
  esac
done
printf 'SUPER+Q killactive\n'
EOF
chmod +x "$TEST_DIR/bin/hyprkeys"
: >"$TEST_DIR/bin/calls.log"
printf 'bind = SUPER, Q, killactive\n' >"$TEST_DIR/mock-hypr.conf"
# Point settings keybinds_config at TEST_DIR file for hermetic runs
perl -i -pe 's|"keybinds_config": "/tmp/mock-hypr.conf"|"keybinds_config": "'"$TEST_DIR"'/mock-hypr.conf"|' \
  "$TEST_DIR/data/waybar-settings.jsonc"
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/waybar-settings.sh"
)
WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" \
  "$TEST_DIR/scripts/keybindhint-click.sh" >/dev/null 2>&1 || true
if ! grep -q "config=${TEST_DIR}/mock-hypr.conf" "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: keybindhint should pass hypr_tools.keybinds_config to hyprkeys. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi
# Terminal fallback when rofi/wofi unavailable
sed -e 's/command -v rofi/false/' -e 's/command -v wofi/false/' \
  "$TEST_DIR/scripts/keybindhint-click.sh" >"$TEST_DIR/scripts/keybindhint-click-norofi.sh"
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
cat >"$TEST_DIR/bin/checkupdates" <<'EOF'
#!/usr/bin/env sh
printf 'pkg 1-1 -> 1-2\n'
EOF
chmod +x "$TEST_DIR/bin/checkupdates"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/updates-review.sh" >/dev/null 2>&1 || true
if ! grep -q 'width: 111px' "$TEST_DIR/bin/calls.log" || ! grep -q 'height: 222px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: updates-review should use rofi.updates size. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# powerprofiles rofi size
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/powerprofiles-click.sh" menu >/dev/null 2>&1 || true
if ! grep -q 'width: 333px' "$TEST_DIR/bin/calls.log" || ! grep -q 'lines: 4' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: powerprofiles menu should use rofi.powerprofiles size. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# kdeconnect rofi width
: >"$TEST_DIR/bin/calls.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/kdeconnect-menu.sh" >/dev/null 2>&1 || true
if ! grep -q 'width: 444px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: kdeconnect-menu should use rofi.kdeconnect.width. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# vaults.py / device-notifier.py rofi widths
mkdir -p "$TEST_DIR/Vaults/TestVault" "$TEST_DIR/Vaults/.TestVault"
touch "$TEST_DIR/Vaults/.TestVault/gocryptfs.conf"
: >"$TEST_DIR/bin/calls.log"
HOME="$TEST_DIR" WAYBAR_HOME="$TEST_DIR" python3 "$TEST_DIR/scripts/vaults.py" --menu >/dev/null 2>&1 || true
if ! grep -q 'width: 555px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: vaults.py should use rofi.vaults.width. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

: >"$TEST_DIR/bin/calls.log"
cat >"$TEST_DIR/bin/lsblk" <<'EOF'
#!/usr/bin/env sh
printf '{"blockdevices":[]}\n'
EOF
chmod +x "$TEST_DIR/bin/lsblk"
HOME="$TEST_DIR" WAYBAR_HOME="$TEST_DIR" python3 "$TEST_DIR/scripts/device-notifier.py" --menu >/dev/null 2>&1 || true
if ! grep -q 'width: 666px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: device-notifier.py should use rofi.device_notifier.width. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

echo "PASS: polish runtime settings wiring"

# --- pre-commit helper dry checks (script exists + bash -n) ---
if ! bash -n "$ROOT/scripts/pre-commit-check-secrets.sh"; then
  echo "FAIL: pre-commit-check-secrets.sh syntax error" >&2
  fail=1
else
  echo "PASS: pre-commit-check-secrets.sh syntax"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "FAIL: secrets/settings tests had failures" >&2
  exit 1
fi

echo "PASS: All secrets/settings exposure tests passed."
exit 0
