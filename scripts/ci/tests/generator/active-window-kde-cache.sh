#!/usr/bin/env bash
# KDE active-window: per-output cache writes, activeOutputName fallback, scroll seeding.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "active-window-kde-cache"
waybar_test_gen_sandbox

echo "Testing KDE active-window per-output cache + scroll seeding..."

# Source contracts: flush must resolve output and write per-output raws.
aw_py="$TEST_DIR/scripts/lib/kde_listener/active_window.py"
for needle in \
  'activeOutputName' \
  '_resolve_active_output' \
  '_known_output_names' \
  'active-window-title-' \
  'Two-string callDBus'; do
  if ! grep -Fq "$needle" "$aw_py"; then
    echo "FAIL: active_window.py missing $needle" >&2
    fail=1
  fi
done
# Guard against reintroducing a 3-arg update — callDBus with a third string
# silently failed on Plasma (CI enforces two-arg ss only).
if grep -Fq '"update", title, app, output' "$aw_py" || grep -Fq 'type="s" name="output"' "$aw_py"; then
  echo "FAIL: KDE update must stay two-arg (ss); third arg broke callDBus" >&2
  fail=1
fi

scroll="$TEST_DIR/scripts/workspaces/active-window-scroll.sh"
if ! grep -Fq '_need_seed' "$scroll"; then
  echo "FAIL: active-window-scroll.sh should seed empty per-output raws" >&2
  fail=1
fi
if ! grep -Fq 'active-window-title.raw' "$scroll"; then
  echo "FAIL: active-window-scroll.sh should fall back to global raw" >&2
  fail=1
fi

# Unit-test flush_active_window_update without real PyGObject / KWin.
python3 - "$TEST_DIR" <<'PY' || fail=1
import json
import os
import subprocess
import sys
import types
from pathlib import Path
from unittest.mock import patch

test_dir = Path(sys.argv[1])
cache = test_dir / "cache-aw"
cache.mkdir(parents=True, exist_ok=True)

# Stub gi before importing the mixin (CI generator job has no PyGObject).
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
    h.pending_title = ""
    h.pending_app = ""
    h.pending_output = ""
    h.active_window_timeout_id = 0
    return h


# 1) Explicit output writes that monitor's raw/json + global.
for p in cache.glob("active-window*"):
    p.unlink()
h = make_harness()
h.pending_title = "Terminal — DP-1"
h.pending_output = "DP-1"
h.flush_active_window_update()
raw = (cache / "active-window-title-DP-1.raw").read_text(encoding="utf-8")
assert "Terminal" in raw, raw
assert (cache / "active-window-DP-1.json").is_file()
assert (cache / "active-window-title.raw").read_text(encoding="utf-8") == raw
print("PASS: explicit output writes per-output + global caches")

# 2) Empty output → resolve via qdbus activeOutputName.
for p in cache.glob("active-window*"):
    p.unlink()
h = make_harness()
h.pending_title = "Resolved Via Qdbus"
h.pending_output = ""


def fake_run(cmd, **kwargs):
    joined = " ".join(cmd) if isinstance(cmd, (list, tuple)) else str(cmd)
    if "activeOutputName" in joined:
        return subprocess.CompletedProcess(cmd, 0, stdout="DP-3\n", stderr="")
    return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")


with patch("kde_listener.active_window.subprocess.run", side_effect=fake_run):
    h.flush_active_window_update()
got = (cache / "active-window-title-DP-3.raw").read_text(encoding="utf-8")
assert got == "Resolved Via Qdbus", got
assert not (cache / "active-window-title-DP-1.raw").exists()
print("PASS: empty output falls back to KWin.activeOutputName")

# 3) No output + no qdbus → mirror to every known per-output raw.
for p in cache.glob("active-window*"):
    p.unlink()
(cache / "active-window-title-DP-1.raw").write_text("", encoding="utf-8")
(cache / "active-window-title-DP-3.raw").write_text("stale", encoding="utf-8")
h = make_harness()
h.pending_title = "Mirrored Title"
h.pending_output = ""


def empty_run(cmd, **kwargs):
    return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")


with patch("kde_listener.active_window.subprocess.run", side_effect=empty_run):
    h.flush_active_window_update()
assert (cache / "active-window-title-DP-1.raw").read_text(encoding="utf-8") == "Mirrored Title"
assert (cache / "active-window-title-DP-3.raw").read_text(encoding="utf-8") == "Mirrored Title"
assert (cache / "active-window-title.raw").read_text(encoding="utf-8") == "Mirrored Title"
print("PASS: unknown output mirrors title to known per-output raws")

# 4) Unwritable per-output raw is dropped then rewritten.
blocked = cache / "active-window-title-DP-1.raw"
blocked.write_text("blocked", encoding="utf-8")
blocked.chmod(0o444)
h = make_harness()
h.pending_title = "After Unblock"
h.pending_output = "DP-1"
h.flush_active_window_update()
assert blocked.read_text(encoding="utf-8") == "After Unblock"
# restore for sandbox cleanup
blocked.chmod(0o644)
print("PASS: unwritable per-output raw is replaced")

# 5) Desktop / empty title still updates caches.
h = make_harness()
h.pending_title = ""
h.pending_output = "DP-1"
h.flush_active_window_update()
data = json.loads((cache / "active-window-DP-1.json").read_text(encoding="utf-8"))
assert data["class"] == "desktop", data
assert (cache / "active-window-title-DP-1.raw").read_text(encoding="utf-8") == ""
print("PASS: empty title writes desktop class to per-output cache")
PY

# Scroll script: empty per-output raw seeded from global on KDE.
# Keep stderr so gen helper can dump generator output on failure.
if ! waybar_test_gen_modules >/dev/null; then
  echo "FAIL: generate-settings failed before scroll seed test" >&2
  fail=1
fi
python3 - <<'PY'
import json
from pathlib import Path
import os
settings = Path(os.environ["WAYBAR_HOME"]) / "data" / "waybar-settings.json"
data = json.loads(settings.read_text())
data.setdefault("active_window", {})["zscroll"] = False
data["active_window"]["max_length"] = 40
data["active_window"]["per_output"] = True
settings.write_text(json.dumps(data))
PY

CACHE="$TEST_DIR/cache-scroll"
mkdir -p "$CACHE/waybar"
printf '%s' 'Global Seeded Title' >"$CACHE/waybar/active-window-title.raw"
: >"$CACHE/waybar/active-window-title-DP-1.raw"

out_file="$TEST_DIR/aw-scroll-seed.log"
XDG_CACHE_HOME="$CACHE" WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_COMPOSITOR=kde WAYBAR_OUTPUT_NAME=DP-1 \
  bash "$TEST_DIR/scripts/workspaces/active-window-scroll.sh" DP-1 >"$out_file" 2>&1 &
scroll_pid=$!
sleep 0.5
kill "$scroll_pid" 2>/dev/null || true
wait "$scroll_pid" 2>/dev/null || true

seeded=$(cat "$CACHE/waybar/active-window-title-DP-1.raw" 2>/dev/null || true)
if [ "$seeded" != "Global Seeded Title" ]; then
  echo "FAIL: expected empty DP-1 raw seeded from global, got: [$seeded]" >&2
  cat "$out_file" >&2 || true
  fail=1
else
  echo "PASS: active-window-scroll seeds empty per-output raw from global"
fi

if ! grep -q 'Global Seeded Title' "$out_file"; then
  echo "FAIL: scroll output should include seeded title" >&2
  cat "$out_file" >&2 || true
  fail=1
fi

# ensure_cache_writable helper
# shellcheck source=../../../../scripts/lib/waybar-cache-helpers.sh
. "$TEST_DIR/scripts/lib/waybar-cache-helpers.sh"
blocked="$TEST_DIR/cache-helpers/blocked.json"
mkdir -p "$(dirname "$blocked")"
echo '{}' >"$blocked"
chmod a-w "$blocked"
ensure_cache_writable "$blocked"
if [ -e "$blocked" ]; then
  echo "FAIL: ensure_cache_writable should remove unwritable cache file" >&2
  chmod u+w "$blocked" 2>/dev/null || true
  fail=1
else
  echo "PASS: ensure_cache_writable removes unwritable files"
fi

waybar_test_end
