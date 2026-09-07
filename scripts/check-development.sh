#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
pnpm install --frozen-lockfile --ignore-scripts
if [[ $(uname -s) == Linux ]]; then
  make check
else
  # Linux fixture suites inspect process and desktop-specific behavior.
  make check-syntax check-python check-ruff check-suite-inventory check-docs-index \
    check-systemd check-shfmt check-gitleaks check-stylelint check-markdownlint
fi
python3 -m unittest discover -s tests -p test_development_container.py
shellcheck scripts/check-development.sh
ruff check scripts/development-container.py tests/test_development_container.py
actionlint
zizmor --offline --min-severity medium --min-confidence medium .github
