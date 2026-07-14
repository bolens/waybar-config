#!/usr/bin/env bash
# Module polish: VPN/Tailscale refresh, cooling-click, docker tooltips, listener contracts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "vpn-cooling-refresh"
waybar_test_gen_sandbox

if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed" >&2
  fail=1
fi

echo "Testing VPN/Tailscale generator wiring..."
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network-custom.generated.jsonc" \
  '
    (."custom/vpnstatus"."on-click-middle" | test("vpn-status\\.sh --refresh"))
    and (."custom/vpnstatus"."on-click-middle" | test("waybar-signal\\.sh vpn"))
    and (."custom/vpnstatus"."on-click-right" | test("nm-connection-editor"))
  ' \
  "vpnstatus should wire middle refresh + right settings"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network-custom.generated.jsonc" \
  '
    (."custom/tailscale"."on-click-middle" | test("tailscale-status\\.sh --refresh"))
    and (."custom/tailscale"."on-click-middle" | test("waybar-signal\\.sh tailscale"))
  ' \
  "tailscale should wire middle refresh + signal"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network-custom.generated.jsonc" \
  '
    (."custom/yggdrasil"."on-click-middle" | test("yggdrasil-status\\.sh --refresh"))
    and (."custom/yggdrasil"."on-click-middle" | test("waybar-signal\\.sh yggdrasil"))
    and (."custom/ipfs"."on-click-middle" | test("ipfs-status\\.sh --refresh"))
    and (."custom/ipfs"."on-click-middle" | test("waybar-signal\\.sh ipfs"))
    and ."custom/yggdrasil".signal == 37
    and ."custom/ipfs".signal == 38
  ' \
  "yggdrasil/ipfs should wire middle refresh + reserved signals"

echo "Testing weather/github signal wiring..."
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '
    ."custom/weather".signal == 34
    and (."custom/weather"."on-click-middle" | test("waybar-signal\\.sh weather"))
    and ."custom/github".signal == 35
    and (."custom/github"."on-click-middle" | test("waybar-signal\\.sh github"))
  ' \
  "weather/github should expose signals and signal on middle-click"

echo "Testing keyed refresh (no numeric waybar-signal.sh in generators)..."
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '
    (."custom/kdeconnect"."on-click-middle" | test("waybar-signal\\.sh kdeconnect"))
    and (."custom/device-notifier"."on-click-right" | test("waybar-signal\\.sh device_notifier"))
    and (."custom/vaults"."on-click-right" | test("waybar-signal\\.sh vaults"))
    and (."custom/touchpad"."on-click-right" | test("waybar-signal\\.sh touchpad"))
    and (."custom/rgb"."on-click-middle" | test("waybar-signal\\.sh rgb"))
    and (."custom/asusctl"."on-click-middle" | test("waybar-signal\\.sh asusctl"))
    and (."custom/device-battery"."on-click-middle" | test("waybar-signal\\.sh device_battery"))
  ' \
  "utilities refresh clicks should use signals.* keys"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '
    (."custom/coolercontrol"."on-click-middle" | test("waybar-signal\\.sh coolercontrol"))
    and (."custom/openlinkhub"."on-click-middle" | test("waybar-signal\\.sh openlinkhub"))
    and (."custom/homelab"."on-click-middle" | test("waybar-signal\\.sh homelab"))
  ' \
  "system polling modules should signal on middle-click refresh"
if grep -RE 'waybar-signal\.sh [0-9]+' \
  "$TEST_DIR/modules/"*.generated.jsonc \
  "$TEST_DIR/scripts/generate/"*.sh 2>/dev/null; then
  echo "FAIL: generators/modules must not bake numeric waybar-signal.sh offsets" >&2
  fail=1
fi

echo "Testing fans/liquidctl → cooling-click..."
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" \
  '
    (."custom/fans"."on-click" | test("cooling-click\\.sh open"))
    and (."custom/fans"."on-click-right" | test("cooling-click\\.sh menu"))
    and (."custom/liquidctl"."on-click" | test("cooling-click\\.sh open"))
    and (."custom/liquidctl"."on-click-right" | test("cooling-click\\.sh menu"))
  ' \
  "fans/liquidctl should prefer cooling-click helper"

if [ ! -x "$TEST_DIR/scripts/system/cooling-click.sh" ]; then
  echo "FAIL: cooling-click.sh missing" >&2
  fail=1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/system/cooling-click.sh" \
  "cooling-click.sh failed bash -n"
waybar_test_assert_bash_n "$TEST_DIR/scripts/listeners/vpn-tailscale-listener.sh" \
  "vpn-tailscale-listener.sh failed bash -n"
waybar_test_assert_bash_n "$TEST_DIR/scripts/listeners/album-art-listener.sh" \
  "album-art-listener.sh failed bash -n"

if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME=vpn-tailscale' \
  "$TEST_DIR/scripts/listeners/vpn-tailscale-listener.sh"; then
  echo "FAIL: vpn-tailscale-listener.sh must set WAYBAR_LISTENER_LOCK_NAME=vpn-tailscale" >&2
  fail=1
fi
if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME=album-art' \
  "$TEST_DIR/scripts/listeners/album-art-listener.sh"; then
  echo "FAIL: album-art-listener.sh must set WAYBAR_LISTENER_LOCK_NAME=album-art" >&2
  fail=1
fi
if ! grep -q 'vpn-tailscale' "$TEST_DIR/scripts/infra/waybar-healthcheck.sh"; then
  echo "FAIL: waybar-healthcheck.sh should heal vpn-tailscale listener" >&2
  fail=1
fi
if ! grep -q 'album-art' "$TEST_DIR/scripts/infra/waybar-healthcheck.sh"; then
  echo "FAIL: waybar-healthcheck.sh should heal album-art listener" >&2
  fail=1
fi
if ! grep -q 'vpn-tailscale-listener' "$TEST_DIR/scripts/infra/waybar-launch.sh"; then
  echo "FAIL: waybar-launch.sh should start vpn-tailscale-listener" >&2
  fail=1
fi
if ! grep -q 'album-art-listener' "$TEST_DIR/scripts/infra/waybar-launch.sh"; then
  echo "FAIL: waybar-launch.sh should start album-art-listener" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.updates.enable_aur == true' \
  "updates.enable_aur should default true"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '(.homelab.targets | length) >= 1' \
  "homelab.targets should be populated"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.signals.weather == 34 and .signals.github == 35 and .signals.album_art == 36 and .signals.yggdrasil == 37 and .signals.ipfs == 38' \
  "new signal offsets should be reserved in settings"

echo "Testing cooling-click CoolerControl preference (hermetic)..."
mkdir -p "$TEST_DIR/scripts/tools" "$TEST_DIR/click-log"
: >"$TEST_DIR/click-log/opens.log"
cat >"$TEST_DIR/scripts/tools/app-open.sh" <<EOF
#!/usr/bin/env sh
printf 'open:%s\n' "\$*" >>"$TEST_DIR/click-log/opens.log"
EOF
cat >"$TEST_DIR/scripts/tools/app-open-key.sh" <<EOF
#!/usr/bin/env sh
printf 'key:%s\n' "\$1" >>"$TEST_DIR/click-log/opens.log"
EOF
chmod +x "$TEST_DIR/scripts/tools/app-open.sh" "$TEST_DIR/scripts/tools/app-open-key.sh"

: >"$TEST_DIR/click-log/opens.log"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_TEST_COOLERCONTROL_UP=1 \
  "$TEST_DIR/scripts/system/cooling-click.sh" open nvtop || true
if ! grep -q 'open:xdg-open' "$TEST_DIR/click-log/opens.log"; then
  echo "FAIL: cooling-click should open CoolerControl UI when reachable" >&2
  cat "$TEST_DIR/click-log/opens.log" >&2 || true
  fail=1
fi

: >"$TEST_DIR/click-log/opens.log"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_TEST_COOLERCONTROL_UP=0 \
  "$TEST_DIR/scripts/system/cooling-click.sh" open nvtop || true
if ! grep -q 'key:nvtop' "$TEST_DIR/click-log/opens.log"; then
  echo "FAIL: cooling-click should fall back to app key when CoolerControl is down" >&2
  cat "$TEST_DIR/click-log/opens.log" >&2 || true
  fail=1
fi

echo "Testing docker unhealthy/restarting name tooltips..."
mkdir -p "$TEST_DIR/scripts/services/containers" "$TEST_DIR/bin"
cp "$ROOT_DIR/scripts/services/containers/docker-status.sh" \
  "$TEST_DIR/scripts/services/containers/"
chmod +x "$TEST_DIR/scripts/services/containers/docker-status.sh"
waybar_test_install_path_stubs
waybar_test_write_bin_stub docker <<'EOF'
#!/usr/bin/env sh
# Match docker-status.sh invocations without depending on host docker.
case "$1" in
  info)
    # docker info --format '{{.ServerVersion}}' | Swarm LocalNodeState
    if printf '%s' "$*" | grep -q 'ServerVersion'; then
      printf '%s\n' '24.0.0'
    elif printf '%s' "$*" | grep -q 'Swarm'; then
      printf '%s\n' 'inactive'
    else
      printf '%s\n' '24.0.0'
    fi
    ;;
  ps)
    printf '%s\n' 'bad-app|Up 2 hours (unhealthy)|nginx'
    printf '%s\n' 'ok-app|Up 1 hour|redis'
    printf '%s\n' 'boot|Restarting (1) seconds ago|busybox'
    ;;
  images | volume | stack)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
# docker-status also shells out to `docker images -q` / `volume ls` / `info` Swarm —
# keep stubs permissive. Prefer PATH stub over host docker.
DOCKER_CACHE=$(mktemp -d)
docker_out=$(
  PATH="$TEST_DIR/bin:$PATH" \
    XDG_CACHE_HOME="$DOCKER_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    "$TEST_DIR/scripts/services/containers/docker-status.sh" --refresh 2>/dev/null || true
)
waybar_test_assert_jq "$docker_out" \
  '(.tooltip | test("Unhealthy: bad-app")) and (.tooltip | test("Restarting: boot")) and .class == "critical"' \
  "docker tooltip should name unhealthy/restarting containers: $docker_out"
rm -rf "$DOCKER_CACHE"

echo "PASS: vpn/cooling/docker refresh polish"
waybar_test_end
