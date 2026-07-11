#!/usr/bin/env bash
# Unit tests for secrets overlay, i2pd/coolercontrol sync helpers, capture/disk
# settings, and validate-generated-config credential guards.
set -euo pipefail

echo "=== Running secrets / settings exposure tests ==="

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0

# Clear parent-shell fixture/override bleed (including when nested under generator tests).
# shellcheck source=waybar-test-sanitize-env.sh
. "$ROOT/scripts/ci/waybar-test-sanitize-env.sh"
waybar_test_sanitize_env

TEST_DIR=$(mktemp -d)
SUITE_RUNTIME=$(mktemp -d)
export XDG_RUNTIME_DIR="$SUITE_RUNTIME"
trap 'rm -rf "$TEST_DIR" "$SUITE_RUNTIME"' EXIT

mkdir -p "$TEST_DIR/data" "$TEST_DIR/scripts"/{lib,services/{i2pd,coolercontrol,sync,apps,security,devices},ci,tools,workspaces,system,notifications} "$TEST_DIR/i2pd" "$TEST_DIR/varlib"
cp "$ROOT/scripts/lib/waybar-settings.sh" "$ROOT/scripts/lib/capture-lib.sh" "$TEST_DIR/scripts/lib/"
cp "$ROOT/scripts/services/i2pd/i2pd-set-console-pass.sh" "$TEST_DIR/scripts/services/i2pd/"
cp "$ROOT/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh" "$TEST_DIR/scripts/services/coolercontrol/"
cp "$ROOT/scripts/ci/validate-generated-config.sh" "$TEST_DIR/scripts/ci/"
cp "$ROOT/data/waybar-secrets.example.jsonc" "$TEST_DIR/data/"
find "$TEST_DIR/scripts" -name '*.sh' -exec chmod +x {} +

export WAYBAR_HOME="$TEST_DIR"
export WAYBAR_SCRIPTS="$TEST_DIR/scripts"

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
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
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
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
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
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/capture-lib.sh"
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

# Portable XDG defaults when capture dirs are null + env overrides
echo "Testing capture-lib XDG / env portability..."
cp "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc.bak"
(
  cat >"$TEST_DIR/data/waybar-settings.jsonc" <<'JSON'
{
  "capture": {
    "screenshot_dir": null,
    "screenrecord_dir": null,
    "screenrecord_fps": 30
  }
}
JSON
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/capture-lib.sh"
  export HOME="$TEST_DIR/fakehome"
  export XDG_PICTURES_DIR="$TEST_DIR/Pictures"
  export XDG_VIDEOS_DIR="$TEST_DIR/Videos"
  unset WAYBAR_SCREENSHOT_DIR WAYBAR_SCREENRECORD_DIR
  shot=$(capture_screenshot_base_dir)
  rec=$(capture_screenrecord_base_dir)
  if [ "$shot" != "$TEST_DIR/Pictures/Screenshots" ] || [ "$rec" != "$TEST_DIR/Videos/Screenrecordings" ]; then
    echo "FAIL: XDG capture defaults: shot=$shot rec=$rec" >&2
    exit 1
  fi
  export WAYBAR_SCREENSHOT_DIR="/env/shots"
  export WAYBAR_SCREENRECORD_DIR="/env/recs"
  shot2=$(capture_screenshot_base_dir)
  rec2=$(capture_screenrecord_base_dir)
  if [ "$shot2" != "/env/shots" ] || [ "$rec2" != "/env/recs" ]; then
    echo "FAIL: capture env overrides: shot=$shot2 rec=$rec2" >&2
    exit 1
  fi
) || fail=1
mv -f "$TEST_DIR/data/waybar-settings.jsonc.bak" "$TEST_DIR/data/waybar-settings.jsonc"
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)
echo "PASS: capture-lib XDG / env portability"

# --- validate rejects console_pass in compiled settings ---
echo "Testing validate-generated-config console_pass guard..."
mkdir -p "$TEST_DIR/modules" "$TEST_DIR/includes" "$TEST_DIR/layouts"
# minimal generated stubs so validate doesn't fail for missing files
: >"$TEST_DIR/modules/workspaces.generated.jsonc"
echo '{}' >"$TEST_DIR/modules/workspaces.generated.jsonc"
# compile settings then inject forbidden pass into compiled JSON
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)
jq '.services.i2pd.console_pass = "should-not-be-here"' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate-generated-config should reject console_pass in settings JSON" >&2
  fail=1
else
  echo "PASS: validate rejects console_pass in settings"
fi
# restore clean compiled settings (no pass)
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
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
  "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
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
  "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
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
  "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
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
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
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
  "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
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
  "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
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

# --- coolercontrol-set-ui-pass: comprehensive sync coverage ---
echo "Testing coolercontrol-set-ui-pass sync helper..."
CC_SYNC="$TEST_DIR/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh"
if ! bash -n "$CC_SYNC"; then
  echo "FAIL: coolercontrol-set-ui-pass.sh failed bash -n" >&2
  fail=1
fi
if ! grep -q 'coolercontrol' "$TEST_DIR/data/waybar-secrets.example.jsonc"; then
  echo "FAIL: waybar-secrets.example.jsonc missing coolercontrol block" >&2
  fail=1
fi

# Fail closed when secrets empty and no env bootstrap (non-TTY / test mode)
rm -f "$TEST_DIR/data/waybar-secrets.jsonc"
set +e
out_cc_fail=$(
  CC_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  "$CC_SYNC" 2>&1
)
rc_cc_fail=$?
set -e
if [[ "$rc_cc_fail" -eq 0 ]]; then
  echo "FAIL: coolercontrol sync should fail without credentials. Output: $out_cc_fail" >&2
  fail=1
fi

# CHANGE_ME in secrets counts as missing
cat >"$TEST_DIR/data/waybar-secrets.jsonc" <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_pass": "CHANGE_ME",
      "token": "CHANGE_ME"
    }
  }
}
JSON
set +e
out_cc_chg=$(
  CC_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  "$CC_SYNC" 2>&1
)
rc_cc_chg=$?
set -e
if [[ "$rc_cc_chg" -eq 0 ]]; then
  echo "FAIL: CHANGE_ME credentials should be treated as missing. Output: $out_cc_chg" >&2
  fail=1
fi

# Bootstrap pass+token from env; preserve sibling i2pd secret; mode 0600; no leak in output
cat >"$TEST_DIR/data/waybar-secrets.jsonc" <<'JSON'
{
  "services": {
    "i2pd": {
      "console_pass": "overlay-secret-pass-AAAA"
    }
  }
}
JSON
# Stale /root scripts path must not win once WAYBAR_HOME is resolved
export WAYBAR_SCRIPTS=/root/.config/waybar/scripts
out_cc=$(
  CC_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  CC_UI_PASS_ENV="cc-test-ui-pass-BBBB" \
  CC_TOKEN_ENV="cc_testtoken0000000000000000000000" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: coolercontrol-set-ui-pass exited non-zero: $out_cc" >&2
  fail=1
}
unset WAYBAR_SCRIPTS
if grep -F 'cc-test-ui-pass-BBBB' <<<"$out_cc"; then
  echo "FAIL: sync output leaked ui_pass" >&2
  fail=1
fi
if grep -F 'cc_testtoken0000000000000000000000' <<<"$out_cc"; then
  echo "FAIL: sync output leaked token" >&2
  fail=1
fi
mode_cc=$(stat -c '%a' "$TEST_DIR/data/waybar-secrets.jsonc" 2>/dev/null || stat -f '%OLp' "$TEST_DIR/data/waybar-secrets.jsonc")
if [[ "$mode_cc" != "600" && "$mode_cc" != "0600" ]]; then
  echo "FAIL: coolercontrol secrets mode expected 600 (got $mode_cc)" >&2
  fail=1
fi
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got_pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  got_tok=$(waybar_settings_get '.services.coolercontrol.token' '')
  got_user=$(waybar_settings_get '.services.coolercontrol.ui_user' '')
  got_i2pd=$(waybar_settings_get '.services.i2pd.console_pass' '')
  if [[ "$got_pass" != "cc-test-ui-pass-BBBB" ]]; then
    echo "FAIL: coolercontrol ui_pass not written (got: $got_pass)" >&2
    exit 1
  fi
  if [[ "$got_tok" != "cc_testtoken0000000000000000000000" ]]; then
    echo "FAIL: coolercontrol token not written (got: $got_tok)" >&2
    exit 1
  fi
  if [[ "$got_user" != "CCAdmin" ]]; then
    echo "FAIL: coolercontrol ui_user default missing (got: $got_user)" >&2
    exit 1
  fi
  if [[ "$got_i2pd" != "overlay-secret-pass-AAAA" ]]; then
    echo "FAIL: coolercontrol sync clobbered i2pd console_pass" >&2
    exit 1
  fi
) || fail=1

# Idempotent re-run with credentials already present
out_cc2=$(
  CC_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  "$CC_SYNC" 2>&1
)
if ! grep -q 'credentials present\|unchanged\|Done' <<<"$out_cc2"; then
  echo "FAIL: coolercontrol re-run should be idempotent. Output: $out_cc2" >&2
  fail=1
fi
if grep -q 'wrote coolercontrol credentials' <<<"$out_cc2"; then
  echo "FAIL: idempotent re-run should not rewrite secrets. Output: $out_cc2" >&2
  fail=1
fi

# Token-only bootstrap
printf '{}\n' >"$TEST_DIR/data/waybar-secrets.jsonc"
out_tok=$(
  CC_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  CC_TOKEN_ENV="cc_onlytoken1111111111111111111111" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: token-only bootstrap failed: $out_tok" >&2
  fail=1
}
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got=$(waybar_settings_get '.services.coolercontrol.token' '')
  pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' 'MISSING')
  if [[ "$got" != "cc_onlytoken1111111111111111111111" ]]; then
    echo "FAIL: token-only write mismatch (got: $got)" >&2
    exit 1
  fi
  if [[ "$pass" != "MISSING" && -n "$pass" && "$pass" != "null" && "$pass" != "CHANGE_ME" ]]; then
    echo "FAIL: token-only bootstrap should not invent ui_pass (got: $pass)" >&2
    exit 1
  fi
) || fail=1

# Pass-only bootstrap
printf '{}\n' >"$TEST_DIR/data/waybar-secrets.jsonc"
out_pass=$(
  CC_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  CC_UI_PASS_ENV="cc-pass-only-CCCC" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: pass-only bootstrap failed: $out_pass" >&2
  fail=1
}
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  tok=$(waybar_settings_get '.services.coolercontrol.token' 'MISSING')
  if [[ "$got" != "cc-pass-only-CCCC" ]]; then
    echo "FAIL: pass-only write mismatch (got: $got)" >&2
    exit 1
  fi
  if [[ "$tok" != "MISSING" && -n "$tok" && "$tok" != "null" && "$tok" != "CHANGE_ME" ]]; then
    echo "FAIL: pass-only bootstrap should not invent token (got: $tok)" >&2
    exit 1
  fi
) || fail=1

# Partial update: add token when pass already present
out_partial=$(
  CC_TEST_MODE=1 \
  WAYBAR_HOME="$TEST_DIR" \
  CC_TOKEN_ENV="cc_partialtoken2222222222222222222" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: partial token update failed: $out_partial" >&2
  fail=1
}
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got_pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  got_tok=$(waybar_settings_get '.services.coolercontrol.token' '')
  if [[ "$got_pass" != "cc-pass-only-CCCC" ]]; then
    echo "FAIL: partial update clobbered ui_pass (got: $got_pass)" >&2
    exit 1
  fi
  if [[ "$got_tok" != "cc_partialtoken2222222222222222222" ]]; then
    echo "FAIL: partial update did not write token (got: $got_tok)" >&2
    exit 1
  fi
) || fail=1

# Simulated sudo home resolution (CC_TEST_SUDO_HOME)
SUDO_FAKE="$TEST_DIR/sudohome"
mkdir -p "$SUDO_FAKE/.config/waybar"/{data,scripts/{lib,services/coolercontrol}}
cp "$TEST_DIR/scripts/lib/waybar-settings.sh" "$SUDO_FAKE/.config/waybar/scripts/lib/"
cp "$CC_SYNC" "$SUDO_FAKE/.config/waybar/scripts/services/coolercontrol/"
cp "$TEST_DIR/data/waybar-settings.jsonc" "$SUDO_FAKE/.config/waybar/data/"
cp "$TEST_DIR/data/waybar-secrets.example.jsonc" "$SUDO_FAKE/.config/waybar/data/"
chmod +x "$SUDO_FAKE/.config/waybar/scripts/services/coolercontrol/"*.sh
out_sudo=$(
  CC_TEST_MODE=1 \
  HOME=/root \
  WAYBAR_HOME= \
  SUDO_USER=fake-cc-user \
  CC_TEST_SUDO_HOME="$SUDO_FAKE" \
  WAYBAR_SCRIPTS=/root/.config/waybar/scripts \
  CC_UI_PASS_ENV="cc-sudo-pass-DDDD" \
  "$SUDO_FAKE/.config/waybar/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh" 2>&1
) || {
  echo "FAIL: sudo-home resolution bootstrap failed: $out_sudo" >&2
  fail=1
}
if [[ ! -f "$SUDO_FAKE/.config/waybar/data/waybar-secrets.jsonc" ]]; then
  echo "FAIL: sudo-home sync did not write secrets under CC_TEST_SUDO_HOME" >&2
  fail=1
fi
(
  WAYBAR_HOME="$SUDO_FAKE/.config/waybar"
  # shellcheck source=/dev/null
  . "$SUDO_FAKE/.config/waybar/scripts/lib/waybar-settings.sh"
  got=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  if [[ "$got" != "cc-sudo-pass-DDDD" ]]; then
    echo "FAIL: sudo-home secrets mismatch (got: $got)" >&2
    exit 1
  fi
) || fail=1

# Mock curl auth path: must use POST /login (not GET) and Bearer /status
CC_CURL_FAKE="$TEST_DIR/fakebin"
mkdir -p "$CC_CURL_FAKE"
CC_CURL_LOG="$TEST_DIR/curl-args.log"
: >"$CC_CURL_LOG"
cat >"$CC_CURL_FAKE/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>$(printf '%q' "$CC_CURL_LOG")
joined="\$*"
if [[ "\$joined" == *"/status"* && "\$joined" == *"Authorization: Bearer"* ]]; then
  printf '200'
  exit 0
fi
if [[ "\$joined" == *"/login"* ]]; then
  if [[ "\$joined" != *"-X POST"* ]]; then
    printf '405'
    exit 0
  fi
  prev=""
  for a in "\$@"; do
    if [[ "\$prev" == "--netrc-file" && -f "\$a" ]]; then
      if grep -q 'invalid-auth-check' "\$a" 2>/dev/null; then
        printf '401'
        exit 0
      fi
    fi
    prev="\$a"
  done
  printf '200'
  exit 0
fi
printf '000'
exit 0
EOF
chmod +x "$CC_CURL_FAKE/curl"

# Ensure secrets have both creds for auth exercise
cat >"$TEST_DIR/data/waybar-secrets.jsonc" <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_user": "CCAdmin",
      "ui_pass": "cc-auth-pass-EEEE",
      "token": "cc_authtoken333333333333333333333"
    }
  }
}
JSON
out_auth=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
  CC_TEST_MODE=1 \
  CC_FORCE_AUTH_CHECK=1 \
  WAYBAR_HOME="$TEST_DIR" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: forced auth check failed: $out_auth" >&2
  fail=1
}
if ! grep -q 'API auth check: OK' <<<"$out_auth"; then
  echo "FAIL: expected successful mock API auth. Output: $out_auth" >&2
  echo "----- curl log -----" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
if ! grep -E -- '-X POST|.*/login' "$CC_CURL_LOG" >/dev/null 2>&1; then
  # Bearer success may short-circuit before login; ensure either Bearer /status or POST /login was used
  if ! grep -q '/status' "$CC_CURL_LOG"; then
    echo "FAIL: mock curl never saw /status or /login. Log:" >&2
    cat "$CC_CURL_LOG" >&2 || true
    fail=1
  fi
fi
# Bearer-only auth path
: >"$CC_CURL_LOG"
cat >"$TEST_DIR/data/waybar-secrets.jsonc" <<'JSON'
{
  "services": {
    "coolercontrol": {
      "token": "cc_authtoken333333333333333333333"
    }
  }
}
JSON
out_auth_tok=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
  CC_TEST_MODE=1 \
  CC_FORCE_AUTH_CHECK=1 \
  WAYBAR_HOME="$TEST_DIR" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: bearer auth check failed: $out_auth_tok" >&2
  fail=1
}
if ! grep -q 'Bearer token' <<<"$out_auth_tok"; then
  echo "FAIL: expected Bearer token auth OK message. Output: $out_auth_tok" >&2
  fail=1
fi
if ! grep -q 'Authorization: Bearer' "$CC_CURL_LOG"; then
  echo "FAIL: mock curl missing Bearer header. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
# Basic-only auth path must POST /login
: >"$CC_CURL_LOG"
cat >"$TEST_DIR/data/waybar-secrets.jsonc" <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_user": "CCAdmin",
      "ui_pass": "cc-auth-pass-EEEE"
    }
  }
}
JSON
out_auth_basic=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
  CC_TEST_MODE=1 \
  CC_FORCE_AUTH_CHECK=1 \
  WAYBAR_HOME="$TEST_DIR" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: basic auth check failed: $out_auth_basic" >&2
  fail=1
}
if ! grep -q 'Basic login' <<<"$out_auth_basic"; then
  echo "FAIL: expected Basic login auth OK message. Output: $out_auth_basic" >&2
  fail=1
fi
if ! grep -E '(-X POST|/login)' "$CC_CURL_LOG" | grep -q '/login'; then
  echo "FAIL: basic auth must hit POST /login. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
if ! grep -q -- '-X POST' "$CC_CURL_LOG"; then
  echo "FAIL: /login must use POST (OpenAPI). Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
# Password must not appear on curl argv (netrc only)
if grep -F 'cc-auth-pass-EEEE' "$CC_CURL_LOG"; then
  echo "FAIL: ui_pass appeared on curl argv" >&2
  fail=1
fi

# Bearer rejected → ui_pass fallback (sync helper)
: >"$CC_CURL_LOG"
cat >"$CC_CURL_FAKE/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>$(printf '%q' "$CC_CURL_LOG")
joined="\$*"
if [[ "\$joined" == *"/status"* && "\$joined" == *"Authorization: Bearer"* ]]; then
  if [[ "\$joined" == *"cc_bad"* ]]; then
    printf '401'
    exit 0
  fi
  printf '200'
  exit 0
fi
if [[ "\$joined" == *"/login"* ]]; then
  if [[ "\$joined" != *"-X POST"* ]]; then
    printf '405'
    exit 0
  fi
  prev=""
  for a in "\$@"; do
    if [[ "\$prev" == "--netrc-file" && -f "\$a" ]]; then
      if grep -q 'invalid-auth-check' "\$a" 2>/dev/null; then
        printf '401'
        exit 0
      fi
    fi
    prev="\$a"
  done
  printf '200'
  exit 0
fi
printf '000'
exit 0
EOF
chmod +x "$CC_CURL_FAKE/curl"
cat >"$TEST_DIR/data/waybar-secrets.jsonc" <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_user": "CCAdmin",
      "ui_pass": "cc-auth-pass-EEEE",
      "token": "cc_bad_token_should_fallback"
    }
  }
}
JSON
out_auth_fb=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
  CC_TEST_MODE=1 \
  CC_FORCE_AUTH_CHECK=1 \
  WAYBAR_HOME="$TEST_DIR" \
  "$CC_SYNC" 2>&1
) || {
  echo "FAIL: bearer→ui_pass fallback auth check failed: $out_auth_fb" >&2
  fail=1
}
if ! grep -qi 'ui_pass fallback\|trying ui_pass' <<<"$out_auth_fb"; then
  echo "FAIL: expected ui_pass fallback message. Output: $out_auth_fb" >&2
  fail=1
fi
if ! grep -q 'API auth check: OK' <<<"$out_auth_fb"; then
  echo "FAIL: fallback should still OK via ui_pass. Output: $out_auth_fb" >&2
  fail=1
fi
if ! grep -q 'Authorization: Bearer' "$CC_CURL_LOG"; then
  echo "FAIL: fallback should try Bearer first. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
if ! grep -q '/login' "$CC_CURL_LOG"; then
  echo "FAIL: fallback should POST /login. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi

echo "PASS: coolercontrol-set-ui-pass sync helper"

# --- validate rejects coolercontrol secrets in compiled settings ---
echo "Testing validate-generated-config coolercontrol credential guards..."
# Restore clean compiled settings before injecting leaks
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)
jq '.services.coolercontrol.ui_pass = "should-not-be-here"' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject coolercontrol.ui_pass in settings JSON" >&2
  fail=1
else
  echo "PASS: validate rejects coolercontrol.ui_pass in settings"
fi
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)
jq '.services.coolercontrol.token = "cc_should_not_be_here"' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject coolercontrol.token in settings JSON" >&2
  fail=1
else
  echo "PASS: validate rejects coolercontrol.token in settings"
fi
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)

# --- polish runtime script wiring ---
echo "Testing polish runtime settings wiring..."
cp "$ROOT/scripts/services/sync/updates-status.sh" "$TEST_DIR/scripts/services/sync/"
cp "$ROOT/scripts/services/apps/github-status.sh" "$TEST_DIR/scripts/services/apps/"
cp "$ROOT/scripts/services/security/privacy-click.sh" \
  "$ROOT/scripts/services/security/vaults.py" \
  "$TEST_DIR/scripts/services/security/"
cp "$ROOT/scripts/services/sync/updates-review.sh" "$TEST_DIR/scripts/services/sync/"
cp "$ROOT/scripts/services/devices/kdeconnect-menu.sh" \
  "$ROOT/scripts/services/devices/device-notifier.py" \
  "$TEST_DIR/scripts/services/devices/"
cp "$ROOT/scripts/lib/notifications-lib.sh" \
  "$ROOT/scripts/lib/waybar-cache-helpers.sh" \
  "$ROOT/scripts/lib/unicode-animations-lib.sh" \
  "$ROOT/scripts/lib/compositor-session.sh" \
  "$TEST_DIR/scripts/lib/"
cp "$ROOT/scripts/workspaces/keybindhint-click.sh" "$TEST_DIR/scripts/workspaces/"
cp "$ROOT/scripts/system/powerprofiles-click.sh" "$TEST_DIR/scripts/system/"
find "$TEST_DIR/scripts" \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/cache"
export XDG_CACHE_HOME="$TEST_DIR/cache"
# Stubs go first on PATH for polish runtime tests. Keep the pre-stub PATH so
# compositor-gate (later) can use real host tools without checkupdates/rofi mocks.
WAYBAR_TEST_HOST_PATH="$PATH"
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
cat >"$TEST_DIR/scripts/tools/app-open.sh" <<'EOF'
#!/usr/bin/env sh
printf 'app-open %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
EOF
cat >"$TEST_DIR/scripts/lib/compositor-gate.sh" <<'EOF'
#!/usr/bin/env sh
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    *) shift ;;
  esac
done
exec "$@"
EOF
cat >"$TEST_DIR/scripts/lib/waybar-signal.sh" <<'EOF'
#!/usr/bin/env sh
printf 'waybar-signal %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
EOF
chmod +x "$TEST_DIR/scripts/tools/app-open.sh" "$TEST_DIR/scripts/lib/compositor-gate.sh" "$TEST_DIR/scripts/lib/waybar-signal.sh"

# Recompile settings so getters see polish keys
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
)

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
if ! echo "$out" | jq -e '.tooltip | test("AUR updates: 1")' >/dev/null 2>&1; then
  echo "FAIL: updates-status tooltip missing AUR count. out=$out" >&2
  fail=1
fi

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
if ! echo "$out" | jq -e '.tooltip | test("AUR updates: 0")' >/dev/null 2>&1; then
  echo "FAIL: AUR disabled should report 0. out=$out" >&2
  fail=1
fi

# Cross-distro backends (no paru required)
cat >"$TEST_DIR/bin/apt" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "list" ]; then
  printf 'Listing...\npkg/stable 1.0 [upgradable from: 0.9]\n'
fi
EOF
cat >"$TEST_DIR/bin/dnf" <<'EOF'
#!/usr/bin/env sh
printf 'foo.x86_64 1-1\n'
exit 100
EOF
cat >"$TEST_DIR/bin/flatpak" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TEST_DIR/bin/apt" "$TEST_DIR/bin/dnf" "$TEST_DIR/bin/flatpak"
rm -f "$TEST_DIR/bin/checkupdates" # force non-arch if backend not overridden
: >"$TEST_DIR/bin/calls.log"
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
  WAYBAR_UPDATES_BACKEND=apt \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! echo "$out" | jq -e '.tooltip | test("Backend: apt") and test("APT updates: 1")' >/dev/null 2>&1; then
  echo "FAIL: updates-status apt backend. out=$out" >&2
  fail=1
fi
out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$TEST_DIR/cache" WAYBAR_BACKGROUND=1 \
  WAYBAR_UPDATES_BACKEND=dnf \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! echo "$out" | jq -e '.tooltip | test("Backend: dnf") and test("DNF updates: 1")' >/dev/null 2>&1; then
  echo "FAIL: updates-status dnf backend. out=$out" >&2
  fail=1
fi
# Restore Arch stubs for remaining tests
cat >"$TEST_DIR/bin/checkupdates" <<'EOF'
#!/usr/bin/env sh
printf 'checkupdates\n' >>"${WAYBAR_HOME}/bin/calls.log"
exit 0
EOF
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
cat >"$TEST_DIR/bin/apt" <<'EOF'
#!/usr/bin/env sh
printf 'pkg/stable 1.0 [upgradable from: 0.9]\n'
EOF
# Default polish rofi stub returns Close for System Updates — force Upgrade pick
cat >"$TEST_DIR/bin/rofi" <<'EOF'
#!/usr/bin/env sh
printf 'rofi %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
printf '🚀 Upgrade System Now\n'
EOF
chmod +x "$TEST_DIR/bin/apt" "$TEST_DIR/bin/rofi"
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
cat >"$TEST_DIR/bin/checkupdates" <<'EOF'
#!/usr/bin/env sh
printf 'pkg 1-1 -> 1-2\n'
EOF
chmod +x "$TEST_DIR/bin/checkupdates"
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
cat >"$TEST_DIR/bin/lsblk" <<'EOF'
#!/usr/bin/env sh
printf '{"blockdevices":[]}\n'
EOF
chmod +x "$TEST_DIR/bin/lsblk"
HOME="$TEST_DIR" WAYBAR_HOME="$TEST_DIR" python3 "$TEST_DIR/scripts/services/devices/device-notifier.py" --menu >/dev/null 2>&1 || true
if ! grep -q 'width: 666px' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: device-notifier.py should use rofi.device_notifier.width. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

echo "PASS: polish runtime settings wiring"

# --- gitignore: secrets ignored, example kept trackable ---
if ! git -C "$ROOT" check-ignore -q data/waybar-secrets.jsonc; then
  echo "FAIL: data/waybar-secrets.jsonc must be gitignored" >&2
  fail=1
fi
if ! git -C "$ROOT" check-ignore -q data/waybar-secrets.json; then
  echo "FAIL: data/waybar-secrets.json must be gitignored" >&2
  fail=1
fi
if git -C "$ROOT" check-ignore -q data/waybar-secrets.example.jsonc; then
  echo "FAIL: data/waybar-secrets.example.jsonc must NOT be gitignored" >&2
  fail=1
else
  echo "PASS: gitignore secrets vs example"
fi

# --- secrets file mode 600 (CI has no real secrets file; assert here) ---
chmod 644 "$TEST_DIR/data/waybar-secrets.jsonc"
mkdir -p "$TEST_DIR/modules" "$TEST_DIR/includes" "$TEST_DIR/layouts"
printf '{}\n' >"$TEST_DIR/modules/workspaces.generated.jsonc"
printf '{}\n' >"$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject secrets mode 644" >&2
  fail=1
else
  echo "PASS: validate rejects secrets mode 644"
fi
chmod 600 "$TEST_DIR/data/waybar-secrets.jsonc"
mode=$(stat -c '%a' "$TEST_DIR/data/waybar-secrets.jsonc")
if [[ "$mode" != "600" ]]; then
  echo "FAIL: expected secrets mode 600 after chmod, got $mode" >&2
  fail=1
else
  echo "PASS: secrets mode 600 asserted"
fi

# --- compositor-gate real behavior (not the polish stub); host PATH, private runtime ---
# Use HYPRLAND_INSTANCE_SIGNATURE (not WAYBAR_COMPOSITOR) so we exercise session
# detection. Clear the session cache; earlier polish may have called detect_compositor
# under host KDE env and written "kde" into $XDG_RUNTIME_DIR/waybar-compositor.
GATE="$ROOT/scripts/lib/compositor-gate.sh"
rm -f "${SUITE_RUNTIME}/waybar-compositor"
gate_env=(
  env
  -u WAYBAR_COMPOSITOR
  PATH="${WAYBAR_TEST_HOST_PATH:-/usr/bin:/bin}"
  XDG_RUNTIME_DIR="$SUITE_RUNTIME"
  HYPRLAND_INSTANCE_SIGNATURE=test-sig
)
gate_out=$("${gate_env[@]}" "$GATE" --show kde -- echo RAN 2>/dev/null || true)
if ! printf '%s' "$gate_out" | grep -q '"class":"hidden"'; then
  echo "FAIL: compositor-gate --show kde on Hyprland should emit hidden JSON (got: $gate_out)" >&2
  fail=1
fi
gate_run=$("${gate_env[@]}" "$GATE" --show hyprland -- echo RAN 2>/dev/null || true)
if [[ "$gate_run" != "RAN" ]]; then
  echo "FAIL: compositor-gate --show hyprland on Hyprland should exec command (got: $gate_run)" >&2
  fail=1
fi
gate_hide=$("${gate_env[@]}" "$GATE" --hide hyprland -- echo RAN 2>/dev/null || true)
if ! printf '%s' "$gate_hide" | grep -q '"class":"hidden"'; then
  echo "FAIL: compositor-gate --hide hyprland on Hyprland should emit hidden JSON (got: $gate_hide)" >&2
  fail=1
fi
echo "PASS: compositor-gate show/hide"

# --- pre-commit helper: syntax + behavioral blocks ---
if ! bash -n "$ROOT/scripts/ci/pre-commit-check-secrets.sh"; then
  echo "FAIL: pre-commit-check-secrets.sh syntax error" >&2
  fail=1
else
  echo "PASS: pre-commit-check-secrets.sh syntax"
fi

HOOK_REPO=$(mktemp -d)
(
  set -e
  cd "$HOOK_REPO"
  git init -q
  git config user.email "ci@waybar.test"
  git config user.name "waybar-ci"
  mkdir -p data scripts/ci
  cp "$ROOT/scripts/ci/pre-commit-check-secrets.sh" scripts/ci/
  chmod +x scripts/ci/pre-commit-check-secrets.sh
  printf '{}\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  git commit -q -m init
  # Block secrets filename
  printf '{}\n' >data/waybar-secrets.jsonc
  git add -f data/waybar-secrets.jsonc
  if scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should block staged waybar-secrets.jsonc" >&2
    exit 1
  fi
  git reset -q HEAD -- data/waybar-secrets.jsonc
  rm -f data/waybar-secrets.jsonc
  # Block console_pass in settings
  printf '{\n  "services": { "i2pd": { "console_pass": "leak" } }\n}\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  if scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should block console_pass in settings" >&2
    exit 1
  fi
  # Block coolercontrol ui_pass in settings
  printf '{\n  "services": { "coolercontrol": { "ui_pass": "leak" } }\n}\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  if scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should block ui_pass in settings" >&2
    exit 1
  fi
  # Clean stage OK
  printf '{ "bars": { "layer": "overlay" } }\n' >data/waybar-settings.jsonc
  git add data/waybar-settings.jsonc
  if ! scripts/ci/pre-commit-check-secrets.sh; then
    echo "FAIL: pre-commit should allow clean settings" >&2
    exit 1
  fi
  echo "PASS: pre-commit behavioral blocks"
) || fail=1
rm -rf "$HOOK_REPO"

if [[ "$fail" -ne 0 ]]; then
  echo "FAIL: secrets/settings tests had failures" >&2
  exit 1
fi

echo "PASS: All secrets/settings exposure tests passed."
exit 0
