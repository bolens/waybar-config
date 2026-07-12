#!/usr/bin/env bash
# Assert CI push on.paths and dorny filters stay aligned:
# - CSS surfaces stay in generator + validate (+ push)
# - push on.paths ⊇ union of all dorny filter paths (so push CI can start)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CI_YML="$ROOT/.github/workflows/ci.yml"

python3 - "$CI_YML" <<'PY'
import fnmatch
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
fail = 0


def extract_list(after_pattern: str) -> set[str]:
    m = re.search(after_pattern, text, flags=re.S | re.M)
    if not m:
        raise SystemExit(f"FAIL: block not found for {after_pattern!r}")
    body = m.group(1)
    return set(re.findall(r"""^\s+- ['"]([^'"]+)['"]""", body, flags=re.M))


push = extract_list(r"(?m)^  push:\n.*?^    paths:\n((?:      - .+\n)+)")
push_pos = {p for p in push if not p.startswith("!")}
push_neg = {p[1:] for p in push if p.startswith("!")}


def dorny(name: str) -> set[str]:
    m = re.search(
        rf"(?ms)^            {re.escape(name)}:\n((?:              - .+\n)+)",
        text,
    )
    if not m:
        raise SystemExit(f"FAIL: dorny filter {name!r} not found")
    return set(re.findall(r"""^\s+- ['"]([^'"]+)['"]""", m.group(1), flags=re.M))


# Keep in sync with filters: | keys under dorny/paths-filter in ci.yml.
DORNY_FILTERS = (
    "workflow",
    "scripts",
    "generator",
    "generator_nonscript",
    "secrets",
    "validate",
    "systemd",
)

filters = {name: dorny(name) for name in DORNY_FILTERS}

# Discover unexpected / missing filter keys in the YAML block.
filt_block = re.search(r"(?ms)filters: \|\n((?:            .+\n)+)", text)
if not filt_block:
    raise SystemExit("FAIL: dorny filters: | block not found")
found_keys = re.findall(r"(?m)^            ([A-Za-z0-9_]+):\s*$", filt_block.group(1))
extra = sorted(set(found_keys) - set(DORNY_FILTERS))
missing_keys = sorted(set(DORNY_FILTERS) - set(found_keys))
if extra:
    print(f"FAIL: dorny filters not checked by this script: {', '.join(extra)}", file=sys.stderr)
    fail = 1
if missing_keys:
    print(f"FAIL: expected dorny filters missing from ci.yml: {', '.join(missing_keys)}", file=sys.stderr)
    fail = 1

generator = filters["generator"]
generator_nonscript = filters["generator_nonscript"]
validate = filters["validate"]

must_push = ["style.css", "theme.css", "user-style/**", "theme/**", "scripts/**"]
for p in must_push:
    if p not in push_pos:
        print(f"FAIL: push on.paths missing {p!r}", file=sys.stderr)
        fail = 1

must_gen = ["style.css", "user-style/**", "theme.css", "theme/**", "scripts/**"]
for label, bag in (("generator", generator), ("generator_nonscript", generator_nonscript)):
    for p in must_gen:
        if p == "scripts/**" and label == "generator_nonscript":
            continue
        if p not in bag:
            print(f"FAIL: dorny {label} missing {p!r}", file=sys.stderr)
            fail = 1

for p in ("style.css", "user-style/**", "theme.css", "theme/**"):
    if p not in validate:
        print(f"FAIL: dorny validate missing {p!r}", file=sys.stderr)
        fail = 1

# Generator suites live under scripts/ci/tests/generator — must stay in generator filter.
for p in ("scripts/ci/tests/generator/**", "scripts/**"):
    if p not in generator:
        print(f"FAIL: dorny generator missing {p!r}", file=sys.stderr)
        fail = 1

# Secrets suites path must stay in secrets filter.
if "scripts/ci/tests/secrets/**" not in filters["secrets"]:
    print("FAIL: dorny secrets missing 'scripts/ci/tests/secrets/**'", file=sys.stderr)
    fail = 1


def push_covers(path: str) -> bool:
    """True if a positive push glob would match this dorny path pattern."""
    if path in push_pos:
        return True
    for g in push_pos:
        if g.endswith("/**"):
            root = g[:-3]
            if path == root or path.startswith(root + "/") or path == g:
                return True
        elif g.endswith("/*"):
            root = g[:-2]
            if path == root or (
                path.startswith(root + "/") and "/" not in path[len(root) + 1 :]
            ):
                return True
        else:
            if path == g or fnmatch.fnmatch(path, g):
                return True
    return False


union: set[str] = set()
for paths in filters.values():
    union |= paths

uncovered = sorted(p for p in union if not push_covers(p))
if uncovered:
    print("FAIL: push on.paths does not cover dorny filter path(s):", file=sys.stderr)
    for p in uncovered:
        print(f"  - {p}", file=sys.stderr)
    print(
        "  Keep push on.paths ⊇ union of all dorny filters (ci.yml comment).",
        file=sys.stderr,
    )
    fail = 1

# Markdown exclusions on push (suite-flag resolver ignores md-only scripts hits).
if not any(n.endswith(".md") or n.endswith("*.md") for n in push_neg):
    print("FAIL: push on.paths missing markdown exclusion under scripts/", file=sys.stderr)
    fail = 1

if fail:
    sys.exit(1)
print("ok: CI path filters (CSS surfaces + push⊇dorny + suite globs)")
PY
