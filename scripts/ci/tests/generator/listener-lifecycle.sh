#!/usr/bin/env bash
# listener-ctl lifecycle + KDE signal map + validate-generated-config.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "listener-lifecycle"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed" >&2
  exit 1
fi

echo "Testing listener-ctl lifecycle..."

runtime_stub="$TEST_DIR/runtime"
mkdir -p "$runtime_stub"

# Prefer dash shebang when available so local runs match Ubuntu CI (/bin/sh -> dash).

mock_shebang='#!/usr/bin/env sh'
command -v dash >/dev/null 2>&1 && mock_shebang='#!/usr/bin/env dash'

cat >"$TEST_DIR/scripts/mock-listener.sh" <<MOCK
${mock_shebang}
set -eu
script_dir="\${0%/*}"

# Dash ignores \`. file arg\` — lock name must be in the env (see dock-windows-listener-lock.sh).

WAYBAR_LISTENER_LOCK_NAME="\${WAYBAR_MOCK_LOCK_NAME:-mock-listener}"

# shellcheck source=dock-windows-listener-lock.sh

. "\$WAYBAR_SCRIPTS/listeners/dock-windows-listener-lock.sh"
sleep 30
MOCK

chmod +x "$TEST_DIR/scripts/mock-listener.sh"

XDG_RUNTIME_DIR="$runtime_stub" "$TEST_DIR/scripts/infra/listener-ctl.sh" start "$TEST_DIR/scripts/mock-listener.sh" mock-listener

mock_pid_file="$runtime_stub/waybar-dock-listener-mock-listener.lock.d/pid"
sleep 0.4

if [ ! -f "$mock_pid_file" ] || ! kill -0 "$(cat "$mock_pid_file")" 2>/dev/null; then

  echo "FAIL: listener-ctl start did not leave a live mock-listener lock pid" >&2
  fail=1
else

  XDG_RUNTIME_DIR="$runtime_stub" "$TEST_DIR/scripts/infra/listener-ctl.sh" stop mock-listener
  sleep 0.3

  if [ -f "$mock_pid_file" ] && kill -0 "$(cat "$mock_pid_file" 2>/dev/null)" 2>/dev/null; then

    echo "FAIL: listener-ctl stop left mock-listener running" >&2
    fail=1
  fi

fi

WAYBAR_MOCK_LOCK_NAME=device-notifier XDG_RUNTIME_DIR="$runtime_stub" \
  "$TEST_DIR/scripts/infra/listener-ctl.sh" start "$TEST_DIR/scripts/mock-listener.sh" device-notifier
dn_pid_file="$runtime_stub/waybar-dock-listener-device-notifier.lock.d/pid"
sleep 0.4

if [ ! -f "$dn_pid_file" ] || ! kill -0 "$(cat "$dn_pid_file")" 2>/dev/null; then

  echo "FAIL: listener-ctl start device-notifier mock failed" >&2
  fail=1
else

  XDG_RUNTIME_DIR="$runtime_stub" "$TEST_DIR/scripts/infra/listener-ctl.sh" stop-all
  sleep 0.3

  if [ -f "$dn_pid_file" ] && kill -0 "$(cat "$dn_pid_file" 2>/dev/null)" 2>/dev/null; then

    echo "FAIL: listener-ctl stop-all left device-notifier mock running" >&2
    fail=1
  fi

fi

# device-notifier listener must take the singleton lock (env form — dash-safe)

if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME=device-notifier' "$TEST_DIR/scripts/listeners/device-notifier-listener.sh"; then

  echo "FAIL: device-notifier-listener.sh does not set WAYBAR_LISTENER_LOCK_NAME=device-notifier" >&2
  fail=1
fi

if ! grep -q 'vpn-tailscale' "$TEST_DIR/scripts/infra/listener-ctl.sh"; then
  echo "FAIL: listener-ctl KNOWN_LISTENERS should include vpn-tailscale" >&2
  fail=1
fi
if ! grep -q 'album-art' "$TEST_DIR/scripts/infra/listener-ctl.sh"; then
  echo "FAIL: listener-ctl KNOWN_LISTENERS should include album-art" >&2
  fail=1
fi
if [ ! -x "$TEST_DIR/scripts/listeners/vpn-tailscale-listener.sh" ]; then
  echo "FAIL: vpn-tailscale-listener.sh missing" >&2
  fail=1
fi
if [ ! -x "$TEST_DIR/scripts/listeners/album-art-listener.sh" ]; then
  echo "FAIL: album-art-listener.sh missing" >&2
  fail=1
fi
if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME=vpn-tailscale' "$TEST_DIR/scripts/listeners/vpn-tailscale-listener.sh"; then
  echo "FAIL: vpn-tailscale-listener.sh missing WAYBAR_LISTENER_LOCK_NAME=vpn-tailscale" >&2
  fail=1
fi
if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME=album-art' "$TEST_DIR/scripts/listeners/album-art-listener.sh"; then
  echo "FAIL: album-art-listener.sh missing WAYBAR_LISTENER_LOCK_NAME=album-art" >&2
  fail=1
fi

echo "Testing FIFO listeners open RDWR (avoid EOF exit / open deadlock)..."
for listener in privacy-listener.sh vpn-tailscale-listener.sh album-art-listener.sh; do
  path="$TEST_DIR/scripts/listeners/$listener"
  if ! grep -qE 'exec 3<>"\$fifo"|exec 3<>"\$\{fifo\}"' "$path" \
    && ! grep -Fq 'exec 3<>"$fifo"' "$path"; then
    echo "FAIL: $listener must open FIFO RDWR (exec 3<>\"\$fifo\")" >&2
    fail=1
  fi
  if ! grep -q 'waybar_listener_cleanup' "$path"; then
    echo "FAIL: $listener must define waybar_listener_cleanup (not replace EXIT trap)" >&2
    fail=1
  fi
  if grep -qE '^trap .*EXIT' "$path"; then
    echo "FAIL: $listener must not replace lock EXIT trap (use waybar_listener_cleanup)" >&2
    fail=1
  fi
done
if ! grep -q 'waybar_listener_cleanup' "$TEST_DIR/scripts/listeners/dock-windows-listener-lock.sh"; then
  echo "FAIL: dock-windows-listener-lock.sh should invoke waybar_listener_cleanup on exit" >&2
  fail=1
fi

echo "Testing FIFO RDWR avoids mid-tick EOF (hermetic)..."
fifo_probe=$(mktemp -d)
mkfifo "$fifo_probe/f"
(
  # RDWR open does not block and keeps a writer "alive".
  exec 3<>"$fifo_probe/f"
  (
    sleep 0.05
    echo tick >"$fifo_probe/f"
  ) &
  got=""
  if read -r -t 1 got <&3; then
    printf '%s' "$got" >"$fifo_probe/got"
  fi
  if read -r -t 0.2 _ <&3; then
    echo overdue >"$fifo_probe/second"
  else
    echo blocked >"$fifo_probe/second"
  fi
  exec 3<&-
) &
fid=$!
wait "$fid" 2>/dev/null || true
if [ "$(cat "$fifo_probe/got" 2>/dev/null)" != "tick" ]; then
  echo "FAIL: FIFO probe did not receive tick" >&2
  fail=1
fi
if [ "$(cat "$fifo_probe/second" 2>/dev/null)" != "blocked" ]; then
  echo "FAIL: FIFO RDWR keep-open should block (not EOF) after ephemeral writer closes" >&2
  fail=1
fi
rm -rf "$fifo_probe"

# Launch + healthcheck must know about the new listeners (stop-all + heal).
for needle in vpn-tailscale album-art; do
  if ! grep -q "$needle" "$TEST_DIR/scripts/infra/waybar-launch.sh"; then
    echo "FAIL: waybar-launch.sh should start $needle listener" >&2
    fail=1
  fi
  if ! grep -q "$needle" "$TEST_DIR/scripts/infra/waybar-healthcheck.sh"; then
    echo "FAIL: waybar-healthcheck.sh should heal $needle listener" >&2
    fail=1
  fi
done

# KDE listener loads signals from settings (not only hardcoded RTMIN offsets)

signals_py="$TEST_DIR/scripts/lib/kde_listener/signals.py"
if ! grep -q 'def load_waybar_signals' "$signals_py"; then
  echo "FAIL: kde_listener/signals.py missing load_waybar_signals" >&2
  fail=1
fi

# Active-window title uses file cache + zscroll; listener must not RTMIN-poke Waybar for it.
if grep -rq 'waybar_rtmin("active_window")' "$TEST_DIR/scripts/lib/kde_listener/" "$TEST_DIR/scripts/listeners/active-window-listener-kde.py"; then
  echo "FAIL: KDE listener should not emit waybar_rtmin(\"active_window\")" >&2
  fail=1
fi

python3 - "$TEST_DIR" <<'PY' || fail=1
import json, os, sys
from pathlib import Path
test_dir = Path(sys.argv[1])
settings = {
    "signals": {
        "workspaces": 43,
        "notifications": 44,
        "dock_windows": 45,
    }

}

cfg = test_dir / "data" / "waybar-settings.json"
cfg.write_text(json.dumps(settings))

sys.path.insert(0, str(test_dir / "scripts" / "lib"))
os.environ["WAYBAR_HOME"] = str(test_dir)
from kde_listener.signals import load_waybar_signals, waybar_rtmin

signals = load_waybar_signals()
assert signals["workspaces"] == 43, signals
assert signals["notifications"] == 44, signals
assert signals["dock_windows"] == 45, signals
assert "active_window" not in signals, signals

# defaults still present for unspecified keys

assert "clipboard" in signals and isinstance(signals["clipboard"], int)

# waybar_rtmin should not raise with DEVNULL-only kwargs
# Rebind SIGNALS so waybar_rtmin uses the tested map
import kde_listener.signals as sigmod
sigmod.SIGNALS = signals
waybar_rtmin("workspaces")
print("PASS: KDE signal map loader unit test")
PY

# Restore full settings after KDE unit test mutated waybar-settings.json

waybar_test_gen_restore_sot

# Re-generate from restored jsonc so later override tests start clean

waybar_test_gen_default

# validate-generated-config contract script (after full restore/regen)

if ! WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null; then
  echo "FAIL: validate-generated-config.sh failed on default generated tree" >&2
  fail=1
fi

echo "PASS: listener-ctl lifecycle"
waybar_test_end
