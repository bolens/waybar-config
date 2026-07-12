#!/usr/bin/env bash
# Assert critical CSS surfaces are in dorny generator filters + push on.paths.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CI_YML="$ROOT/.github/workflows/ci.yml"

python3 - "$CI_YML" <<'PY'
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
    paths = set(re.findall(r"""^\s+- ['"]([^'"]+)['"]""", body, flags=re.M))
    return paths

push = extract_list(r"(?m)^  push:\n.*?^    paths:\n((?:      - .+\n)+)")

# Dorny filter blocks live inside `filters: |` literal — match indented keys.
def dorny(name: str) -> set[str]:
    m = re.search(
        rf"(?ms)^            {re.escape(name)}:\n((?:              - .+\n)+)",
        text,
    )
    if not m:
        raise SystemExit(f"FAIL: dorny filter {name!r} not found")
    return set(re.findall(r"""^\s+- ['"]([^'"]+)['"]""", m.group(1), flags=re.M))

generator = dorny("generator")
generator_nonscript = dorny("generator_nonscript")
validate = dorny("validate")

must_push = ["style.css", "theme.css", "user-style/**", "theme/**", "scripts/**"]
for p in must_push:
    if p not in push:
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

# Validate should still cover CSS entrypoints (drift / schema adjacent).
for p in ("style.css", "user-style/**", "theme.css", "theme/**"):
    if p not in validate:
        print(f"FAIL: dorny validate missing {p!r}", file=sys.stderr)
        fail = 1

if fail:
    sys.exit(1)
print("ok: CI path filters include style.css / user-style / theme for generator + validate")
PY
