#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
pnpm install --frozen-lockfile --ignore-scripts
if [[ $(uname -s) == Linux ]]; then
  # Complete CI must not silently skip the hosted GTK3 parser gate.
  python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk; Gtk.CssProvider()'
  make check
else
  # Linux fixture suites inspect process and desktop-specific behavior.
  make check-syntax check-python check-ruff check-suite-inventory check-docs-index \
    check-systemd check-shfmt check-gitleaks check-stylelint check-markdownlint
fi
python3 -m unittest discover -s tests -p test_development_container.py
python3 -m unittest discover -s tests -p test_ci_container_path.py
find scripts -type f -name '*.sh' -print0 | xargs -0 shellcheck --severity=warning
ruff check scripts/development-container.py tests/test_development_container.py scripts/prepare-ci-container.py tests/test_ci_container_path.py
actionlint
zizmor --offline --min-severity medium --min-confidence medium .github
