# Waybar config — local developer tasks
#
# Usage: make check | make generate | make check-syntax | make install-hooks

WAYBAR_HOME ?= $(CURDIR)
WAYBAR_SCRIPTS ?= $(WAYBAR_HOME)/scripts
export WAYBAR_HOME WAYBAR_SCRIPTS

GENERATOR_TESTS := $(sort $(wildcard scripts/ci/tests/generator/*.sh))
SECRETS_TESTS := $(sort $(wildcard scripts/ci/tests/secrets/*.sh))

.PHONY: check check-fast check-syntax check-python check-ruff check-contracts \
	check-generator check-secrets check-systemd check-suite-inventory \
	check-docs-index check-drift check-shfmt check-gitleaks check-stylelint \
	check-gtk-css check-markdownlint check-settings-schema validate generate \
	profile-minimal fmt-shell install-hooks help

help:
	@printf '%s\n' \
		'make check              - full local gate (suites + lint + drift)' \
		'make check-fast         - syntax + contracts + validate + systemd + inventory' \
		'make check-syntax       - bash -n on all scripts/**/*.sh' \
		'make check-python       - python3 -m py_compile on scripts/**/*.py' \
		'make check-ruff         - ruff check scripts/' \
		'make check-contracts' \
		'make check-generator    - scripts/ci/tests/generator/*.sh' \
		'make check-secrets      - scripts/ci/tests/secrets/*.sh' \
		'make check-suite-inventory - CI matrix ↔ on-disk suites' \
		'make check-docs-index   - docs/README.md ↔ docs/*.md + hub backlinks' \
		'make check-drift        - make generate then git diff artifacts' \
		'make check-systemd      - systemd unit templates point at real scripts' \
		'make check-shfmt        - shfmt -d on scripts/' \
		'make check-gitleaks     - secret scan (git-aware)' \
		'make check-stylelint    - CSS lint' \
		'make check-gtk-css      - GTK3/Waybar CSS crash guards' \
		'make check-markdownlint - Markdown lint' \
		'make check-settings-schema - unknown top-level settings keys' \
		'make validate' \
		'make fmt-shell          - shfmt -w scripts/' \
		'make generate           - regenerate settings/modules/css from data/' \
		'make profile-minimal    - merge data/profiles/minimal-groups.jsonc + generate' \
		'make install-hooks      - symlink secrets pre-commit hook'

check: check-syntax check-contracts check-suite-inventory check-docs-index \
	check-generator check-secrets validate check-drift check-systemd \
	check-python check-ruff check-shfmt check-gitleaks check-stylelint \
	check-gtk-css check-markdownlint

check-fast: check-syntax check-contracts check-suite-inventory check-docs-index \
	validate check-systemd check-python

check-syntax:
	@set -euo pipefail; \
	fail=0; \
	while IFS= read -r f; do \
		echo "Checking $$f"; \
		bash -n "$$f" || fail=1; \
	done < <(find scripts -type f -name '*.sh' | sort); \
	exit $$fail

check-python:
	bash scripts/ci/check-python-syntax.sh

check-ruff:
	bash scripts/ci/check-ruff.sh

check-contracts:
	bash scripts/ci/check-shell-contracts.sh

check-suite-inventory:
	bash scripts/ci/check-suite-inventory.sh
	bash scripts/ci/check-ci-path-filters.sh

check-docs-index:
	bash scripts/ci/check-docs-index.sh

check-generator:
	@set -euo pipefail; \
	fail=0; \
	for t in $(GENERATOR_TESTS); do \
		echo ">> $$t"; \
		bash "$$t" || fail=1; \
	done; \
	exit $$fail

check-secrets:
	@set -euo pipefail; \
	fail=0; \
	for t in $(SECRETS_TESTS); do \
		echo ">> $$t"; \
		bash "$$t" || fail=1; \
	done; \
	exit $$fail

check-systemd:
	bash scripts/ci/check-systemd-units.sh

check-drift:
	bash scripts/ci/check-generated-drift.sh

check-shfmt:
	bash scripts/ci/check-shfmt.sh

check-gitleaks:
	bash scripts/ci/check-gitleaks.sh

check-stylelint:
	bash scripts/ci/check-stylelint.sh

check-gtk-css:
	bash scripts/ci/check-gtk-css.sh

check-markdownlint:
	bash scripts/ci/check-markdownlint.sh

check-settings-schema:
	bash scripts/ci/check-settings-schema.sh

validate:
	bash scripts/ci/validate-generated-config.sh
	bash scripts/ci/check-settings-schema.sh

fmt-shell:
	bash scripts/ci/check-shfmt.sh --write

generate:
	bash scripts/generate/generate-settings.sh
	bash scripts/generate/generate-compositor-modules.sh
	bash scripts/generate/generate-workspaces-css.sh
	bash scripts/generate/generate-dock-windows-css.sh
	bash scripts/generate/generate-drawers-css.sh
	bash scripts/generate/generate-groups-css.sh

profile-minimal:
	bash scripts/tools/apply-profile.sh minimal-groups

install-hooks:
	bash scripts/ci/install-hooks.sh
