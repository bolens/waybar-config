#!/usr/bin/env bash
# Shared CI env sanitizer — clear fixture/override vars that poison hermetic tests.
#
# Call at the top of run-generator-tests.sh and run-secrets-and-settings-tests.sh
# so a polluted parent shell (or nested suite invocation) cannot leak:
#   - CoolerControl fixture dirs pointing at deleted mktemps
#   - Fake sysfs roots / host API URLs from a previous case
#   - Compositor overrides that make detect_compositor lie
#
# Intentionally does NOT unset WAYBAR_HOME / WAYBAR_SCRIPTS — suites set those
# immediately after sanitize. `|| true` keeps `set -u` happy when a var was unset.
#
# Source: . "$ROOT/scripts/ci/waybar-test-sanitize-env.sh" && waybar_test_sanitize_env

waybar_test_sanitize_env() {
  # CoolerControl fixtures / credentials / write-probe cache
  unset WAYBAR_CC_FIXTURE_DIR \
    WAYBAR_CC_TOKEN \
    WAYBAR_CC_UI_PASS \
    WAYBAR_CC_UI_USER \
    WAYBAR_CC_FORCE_WRITE_PROBE \
    WAYBAR_CC_WRITE_PROBE_TTL \
    WAYBAR_CC_WRITE_CACHE \
    WAYBAR_CC_API_URL \
    WAYBAR_CC_FORCE_ACTIVE \
    || true

  # OpenLinkHub + sysfs/telemetry roots (CI uses fakes; must not stick)
  unset WAYBAR_OLH_FIXTURE_JSON \
    WAYBAR_OLH_API_URL \
    WAYBAR_OLH_UI_URL \
    WAYBAR_OLH_FORCE_ACTIVE \
    WAYBAR_HWMON_ROOT \
    WAYBAR_THERMAL_ROOT \
    WAYBAR_NVME_HWMON_ROOT \
    WAYBAR_POWER_SUPPLY_ROOT \
    WAYBAR_CORSAIRPSU_PRESENT \
    WAYBAR_LIQUIDCTL_BIN \
    WAYBAR_SOLAAR_BIN \
    WAYBAR_DEVICE_BATTERY_PREFER_SOLAAR \
    WAYBAR_FANCTL_BIN \
    WAYBAR_FANCTL_CONFIG \
    WAYBAR_ASUSCTL_BIN \
    WAYBAR_ASUSCTL_FORCE_ACTIVE \
    WAYBAR_OPENRGB_BIN \
    WAYBAR_RGB_FORCE_CKB \
    WAYBAR_RGB_FORCE_OPENRGB \
    WAYBAR_RGB_FORCE_IDLE \
    || true

  # Capture / updates / bar overrides from a polluted parent shell
  unset WAYBAR_SCREENSHOT_DIR \
    WAYBAR_SCREENRECORD_DIR \
    WAYBAR_SCREENREC_FPS \
    WAYBAR_UPDATES_BACKEND \
    WAYBAR_UPDATES_ENABLE_AUR \
    WAYBAR_COMPOSITOR \
    WAYBAR_OUTPUT \
    WAYBAR_OUTPUT_NAME \
    || true

  # Session bleed — suite may re-export WAYBAR_COMPOSITOR / HYPRLAND_* afterward
  unset HYPRLAND_INSTANCE_SIGNATURE \
    KDE_FULL_SESSION \
    || true
}
