#!/usr/bin/env bash
# Regression: tooltip Pango escape contract (Waybar escape:true vs script escape).
#
# Double-escape shows literal &gt; / &lt; instead of styled/plain text.
# See docs/troubleshooting.md and Waybar issue #3375.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "tooltip-pango-escape"
waybar_test_gen_sandbox

if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before tooltip-pango-escape checks" >&2
  fail=1
fi

echo "Testing generated modules omit escape:true when scripts pre-escape..."
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '
  (."custom/updates" | has("escape") | not)
  or (."custom/updates".escape == false)
' "custom/updates must not set escape:true (emit_waybar_json already escapes)"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/compositor.generated.jsonc" '
  (."custom/active-window" | has("escape") | not)
  or (."custom/active-window".escape == false)
' "custom/active-window must not set escape:true (scripts already escape)"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '
  (."custom/notifications".escape // false) == false
' "custom/notifications keeps escape unset/false so Pango <b> styles tooltips"

# clipboard keeps Waybar-side escape (raw history text; no script escape_markup).
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '
  ."custom/clipboard".escape == true
' "custom/clipboard should keep escape:true (raw clipboard text)"

echo "Testing generators never reintroduce escape:true on pre-escaped modules..."
# Match real jq keys only (not comments like "Do not set escape:true").
if grep -nE '^[[:space:]]*escape:[[:space:]]*true[,[:space:]]*$' \
  "$TEST_DIR/scripts/generate/generate-settings.sh" \
  "$TEST_DIR/scripts/generate/generate-active-window-modules.sh" 2>/dev/null; then
  echo "FAIL: generate-settings / active-window generators must not set escape:true" >&2
  fail=1
fi
notif_escape_ctx=$(
  awk '
    /"custom\/notifications"/ { in_n=1 }
    in_n && /"custom\// && $0 !~ /notifications/ { in_n=0 }
    in_n && /^[[:space:]]*escape:[[:space:]]*true/ { print; exit }
  ' "$TEST_DIR/scripts/generate/generate-utilities-modules.sh"
)
if [ -n "$notif_escape_ctx" ]; then
  echo "FAIL: custom/notifications generator must not set escape:true" >&2
  printf '  %s\n' "$notif_escape_ctx" >&2
  fail=1
fi

echo "Testing emit_waybar_json escapes arrows once (updates tooltip regression)..."
arrow_json=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . \"$TEST_DIR/scripts/lib/waybar-cache-helpers.sh\"
  emit_waybar_json '󰚰  1' 'alsa 1.0 -> 1.1' 'normal'
")
waybar_test_assert_jq "$arrow_json" '
  .tooltip == "alsa 1.0 -&gt; 1.1"
  and (.tooltip | test("&amp;gt;") | not)
' "emit_waybar_json must single-escape -> (not double-escape to &amp;gt;): $arrow_json"

echo "Testing notifications_pango_escape (mako / bash status paths)..."
pango_out=$(WAYBAR_HOME="$TEST_DIR" bash -c '
  . "'"$TEST_DIR"'/scripts/lib/notifications-lib.sh"
  notifications_pango_escape "A & B <tag>"
')
if [ "$pango_out" != "A &amp; B &lt;tag&gt;" ]; then
  echo "FAIL: notifications_pango_escape expected entities, got: [$pango_out]" >&2
  fail=1
fi
if ! grep -Fq 'notifications_pango_escape' \
  "$TEST_DIR/scripts/notifications/notifications-status-mako.sh"; then
  echo "FAIL: mako status should Pango-escape tooltips (escape:false module)" >&2
  fail=1
fi

echo "Testing build_notifications_tooltip (strip HTML, style app, truncate)..."
python3 - "$TEST_DIR" <<'PY' || fail=1
import sys
import types
from pathlib import Path

test_dir = Path(sys.argv[1])
gi = types.ModuleType("gi")
gi.require_version = lambda *a, **k: None
gi_repo = types.ModuleType("gi.repository")
gi_repo.Gio = types.SimpleNamespace()
gi_repo.GLib = types.SimpleNamespace()
sys.modules["gi"] = gi
sys.modules["gi.repository"] = gi_repo
sys.path.insert(0, str(test_dir / "scripts" / "lib"))
from kde_listener.notifications import (  # noqa: E402
    build_notifications_tooltip,
    _strip_markup,
    _pango_escape,
)

assert _strip_markup("Hello <b>world</b>") == "Hello world"
assert _strip_markup("a &amp; b") == "a & b"
assert _pango_escape("A & B <x>") == "A &amp; B &lt;x&gt;"

items = [
    {"app_name": "old", "summary": "first", "body": ""},
    {
        "app_name": "Discord",
        "summary": "Hello <b>world</b> & friends",
        "body": "<i>ignored in tooltip</i>",
    },
    {"app_name": "A & B", "summary": "plain", "body": ""},
    {"app_name": "only-app", "summary": "", "body": ""},
    {"app_name": "extra1", "summary": "x", "body": ""},
    {"app_name": "extra2", "summary": "y", "body": ""},
]
tip = build_notifications_tooltip(6, False, items, max_items=5)
assert tip.startswith("6 unread notification(s)"), tip
# Newest first (list append order)
assert tip.index("<b>extra2</b>") < tip.index("<b>Discord</b>"), tip
assert "<b>Discord</b>: Hello world &amp; friends" in tip, tip
assert "<b>world</b>" not in tip, tip
assert "<i>ignored" not in tip, tip
assert "<b>A &amp; B</b>: plain" in tip, tip
assert "<b>only-app</b>" in tip and "<b>only-app</b>:" not in tip, tip
assert "…and 1 more" in tip, tip
assert "Left: open" in tip, tip

dnd = build_notifications_tooltip(1, True, [{"app_name": "x", "summary": "y"}])
assert "Do not disturb" in dnd and "<b>x</b>: y" in dnd, dnd

empty = build_notifications_tooltip(0, False, [])
assert empty.startswith("Notifications") and "<b>" not in empty, empty

# simulate double-escape anti-pattern on intentional markup
styled = "<b>App</b>: hello"
once = _pango_escape(styled)  # wrong: escaping intentional tags
assert "&lt;b&gt;" in once, once
print("PASS: notification tooltip helpers + truncation + anti-double-escape demo")
PY

echo "Testing active-window cache writes single-escaped titles..."
python3 - "$TEST_DIR" <<'PY' || fail=1
import json
import os
import sys
import types
from pathlib import Path
from unittest.mock import patch

test_dir = Path(sys.argv[1])
cache = test_dir / "cache-aw-pango"
cache.mkdir(parents=True, exist_ok=True)

gi = types.ModuleType("gi")
gi.require_version = lambda *a, **k: None
gi_repo = types.ModuleType("gi.repository")
gi_repo.Gio = types.SimpleNamespace()
gi_repo.GLib = types.SimpleNamespace(
    source_remove=lambda *_: None,
    timeout_add=lambda *_a, **_k: 1,
)
sys.modules["gi"] = gi
sys.modules["gi.repository"] = gi_repo
sys.path.insert(0, str(test_dir / "scripts" / "lib"))
from kde_listener.active_window import ActiveWindowMixin  # noqa: E402


class Harness(ActiveWindowMixin):
    pass


def make_harness():
    h = Harness()
    h.cache_dir = str(cache)
    h.cache_file = str(cache / "active-window.json")
    h.active_window_timeout_id = 0
    h.pending_title = ""
    h.pending_output = ""
    return h


h = make_harness()
h.pending_title = "Foo & Bar <baz>"
h.pending_output = "DP-1"
h.flush_active_window_update()
data = json.loads((cache / "active-window-DP-1.json").read_text(encoding="utf-8"))
assert "&amp;" in data["tooltip"], data
assert "&lt;baz&gt;" in data["tooltip"], data
assert "&amp;amp;" not in data["tooltip"], data  # not double-escaped
assert "&amp;lt;" not in data["text"], data
print("PASS: active-window JSON is single-escaped for Pango")
PY

echo "Testing notifications mixin writes Pango tooltip into status cache..."
python3 - "$TEST_DIR" <<'PY' || fail=1
import json
import sys
import types
from pathlib import Path
from unittest.mock import patch

test_dir = Path(sys.argv[1])
cache = test_dir / "cache-notif-pango"
cache.mkdir(parents=True, exist_ok=True)

gi = types.ModuleType("gi")
gi.require_version = lambda *a, **k: None
gi_repo = types.ModuleType("gi.repository")
gi_repo.Gio = types.SimpleNamespace()
gi_repo.GLib = types.SimpleNamespace()
sys.modules["gi"] = gi
sys.modules["gi.repository"] = gi_repo
sys.path.insert(0, str(test_dir / "scripts" / "lib"))
from kde_listener.notifications import NotificationsMixin  # noqa: E402


class Harness(NotificationsMixin):
    def write_json_atomically(self, path, payload):
        Path(path).write_text(json.dumps(payload), encoding="utf-8")

    def get_inhibited(self):
        return False


h = Harness()
h.count_file = str(cache / "count")
h.status_cache = str(cache / "notifications-status.json")
h.history_cache = str(cache / "history.json")
h.unread_count = 1
h.notifications = [
    {
        "app_name": "cursor",
        "summary": "Approve <b>cmd</b> & go",
        "body": "<img src=x>",
        "id": 1,
    }
]
with patch("kde_listener.notifications.waybar_rtmin"):
    h.update_notifications_cache()
status = json.loads(Path(h.status_cache).read_text(encoding="utf-8"))
tip = status["tooltip"]
assert "<b>cursor</b>: Approve cmd &amp; go" in tip, tip
assert "<b>cmd</b>" not in tip, tip
assert "<img" not in tip, tip
print("PASS: NotificationsMixin status cache tooltip is Pango-safe")
PY

waybar_test_end
