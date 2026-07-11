#!/usr/bin/env bash
# Ensure CI matrix suite lists match scripts/ci/tests/{generator,secrets}/*.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CI_YML="$ROOT/.github/workflows/ci.yml"

python3 - "$ROOT" "$CI_YML" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
ci_yml = pathlib.Path(sys.argv[2])
text = ci_yml.read_text(encoding="utf-8")
fail = 0


def suites_on_disk(subdir: str) -> list[str]:
    d = root / "scripts" / "ci" / "tests" / subdir
    return sorted(p.stem for p in d.glob("*.sh"))


def suites_in_ci(job: str) -> list[str]:
    m = re.search(rf"(?ms)^  {re.escape(job)}:\n(.*?)(?=^  [A-Za-z0-9_-]+:|\Z)", text)
    if not m:
        raise SystemExit(f"FAIL: job {job!r} not found in {ci_yml}")
    block = m.group(1)
    names: list[str] = []
    in_suite = False
    for line in block.splitlines():
        if re.match(r"^        suite:\s*$", line):
            in_suite = True
            continue
        if not in_suite:
            continue
        item = re.match(r"^          - (.+)$", line)
        if item:
            names.append(item.group(1).strip())
            continue
        # End of suite list (next key under strategy/matrix/job).
        if line.strip() == "" or line.startswith("          #"):
            continue
        break
    return names


def check(label: str, job: str, subdir: str) -> None:
    global fail
    disk = suites_on_disk(subdir)
    ci = suites_in_ci(job)
    if set(disk) == set(ci):
        print(f"ok {label}: {len(disk)} suites")
        if disk != ci:
            print(f"note {label}: CI matrix order differs from sorted on-disk names (OK)")
        return
    fail = 1
    print(f"FAIL {label}: CI matrix != scripts/ci/tests/{subdir}/", file=sys.stderr)
    only_disk = sorted(set(disk) - set(ci))
    only_ci = sorted(set(ci) - set(disk))
    if only_disk:
        print(f"  on disk, missing from CI: {', '.join(only_disk)}", file=sys.stderr)
    if only_ci:
        print(f"  in CI, missing on disk: {', '.join(only_ci)}", file=sys.stderr)


check("generator", "generator-tests", "generator")
check("secrets", "secrets-tests", "secrets")
sys.exit(fail)
PY
