#!/usr/bin/env bash
# Preserve the existing local/native entrypoint while grouping CI suppliers.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec bash "$root/scripts/ci/check-spec-kit.sh"
