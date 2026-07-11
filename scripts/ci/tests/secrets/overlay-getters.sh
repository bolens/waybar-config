#!/usr/bin/env bash
# Secrets overlay + settings getters.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "overlay-getters"
waybar_test_secrets_sandbox

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
waybar_test_write_secrets <<'JSON'
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

waybar_test_end
