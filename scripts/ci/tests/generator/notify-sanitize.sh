#!/usr/bin/env bash
# Plasma/Qt HTML → plain text for mako (DrKonqi crash toasts).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "notify-sanitize"
waybar_test_gen_sandbox

waybar_test_assert_file_exists "$TEST_DIR/scripts/lib/notify_markup.py" \
  "notify_markup.py must exist"
waybar_test_assert_file_exists "$TEST_DIR/scripts/listeners/notify-sanitize-listener.py" \
  "notify-sanitize-listener.py must exist"

if [ ! -x "$TEST_DIR/scripts/listeners/notify-sanitize-listener.py" ]; then
  echo "FAIL: notify-sanitize-listener.py must be executable" >&2
  exit 1
fi

# Executable bit is what launch uses; ensure the py listener is +x in the tree.
if [ ! -x "$ROOT_DIR/scripts/listeners/notify-sanitize-listener.py" ]; then
  echo "FAIL: notify-sanitize-listener.py missing +x in repo" >&2
  exit 1
fi

echo "Testing plasma HTML → plain conversion..."
python3 - <<PY
import sys
sys.path.insert(0, "$TEST_DIR/scripts/lib")
from notify_markup import (
    HINT_SANITIZED,
    body_looks_like_plasma_html,
    body_needs_sanitize,
    plasma_html_to_plain,
    sanitize_notification_body,
)

drkonqi = "<html><tt>/usr/bin/zsh</tt> has encountered a fatal error and was closed.</html>"
assert body_looks_like_plasma_html(drkonqi)
assert body_needs_sanitize(drkonqi)
plain = plasma_html_to_plain(drkonqi)
assert plain == "/usr/bin/zsh has encountered a fatal error and was closed.", plain
assert sanitize_notification_body(drkonqi) == plain

command = "<command>%s</command> has encountered a fatal error and was closed." % "/usr/bin/zsh"
assert "zsh" in plasma_html_to_plain(command)
assert "&lt;" not in plasma_html_to_plain(command)

# Intentional freedesktop/Pango markup must pass through unchanged.
ok = "Hello <b>world</b> &amp; friends"
assert sanitize_notification_body(ok) is None
assert not body_looks_like_plasma_html(ok)

assert sanitize_notification_body("plain text") is None
assert HINT_SANITIZED == "x-waybar-notify-sanitized"

# Entities inside Plasma HTML decode once after strip.
ent = "<html><tt>A &amp; B</tt> &lt;ok&gt;</html>"
assert plasma_html_to_plain(ent) == "A & B <ok>", plasma_html_to_plain(ent)
print("PASS: notify_markup conversions")
PY

echo "Testing wiring (launch / healthcheck / listener-ctl)..."
if ! grep -q 'notify-sanitize' "$TEST_DIR/scripts/infra/listener-ctl.sh"; then
  echo "FAIL: listener-ctl KNOWN_LISTENERS must include notify-sanitize" >&2
  exit 1
fi
if ! grep -q 'notify-sanitize-listener' "$TEST_DIR/scripts/infra/waybar-launch.sh"; then
  echo "FAIL: waybar-launch.sh should start notify-sanitize-listener" >&2
  exit 1
fi
if ! grep -q 'notify-sanitize' "$TEST_DIR/scripts/infra/waybar-healthcheck.sh"; then
  echo "FAIL: waybar-healthcheck.sh should heal notify-sanitize" >&2
  exit 1
fi

waybar_test_end
