#!/usr/bin/env bash
# Run the same immutable fleet validator as the retained GitHub workflow.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tooling_ref=c161a6757130ea687def9eb1e81c6a4190488f07
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
git -C "$work" init --quiet
git -C "$work" -c credential.helper= -c core.hooksPath=/dev/null \
  fetch --quiet --depth=1 https://github.com/bolens/.github.git "$tooling_ref"
test "$(git -C "$work" rev-parse FETCH_HEAD)" = "$tooling_ref"
git -C "$work" -c core.hooksPath=/dev/null checkout --quiet --detach FETCH_HEAD
python3 "$work/scripts/validate-spec-kit.py" --expected-version current "$root"
