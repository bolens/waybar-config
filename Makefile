# Waybar config — local developer tasks
#
# Usage: make check | make generate | make check-syntax

WAYBAR_HOME ?= $(CURDIR)
WAYBAR_SCRIPTS ?= $(WAYBAR_HOME)/scripts
export WAYBAR_HOME WAYBAR_SCRIPTS

GENERATOR_TESTS := $(sort $(wildcard scripts/ci/tests/generator/*.sh))
SECRETS_TESTS := $(sort $(wildcard scripts/ci/tests/secrets/*.sh))

.PHONY: check check-syntax check-python check-contracts check-generator check-secrets check-systemd validate generate help

help:
	@printf '%s\n' \
		'make check          - syntax + contracts + generator suites + secrets suites + validate + systemd + python' \
		'make check-syntax   - bash -n on all scripts/**/*.sh' \
		'make check-python   - python3 -m py_compile on scripts/**/*.py' \
		'make check-contracts' \
		'make check-generator - scripts/ci/tests/generator/*.sh' \
		'make check-secrets   - scripts/ci/tests/secrets/*.sh' \
		'make check-systemd  - systemd unit templates point at real scripts' \
		'make validate' \
		'make generate       - regenerate settings/modules/css from data/'

check: check-syntax check-contracts check-generator check-secrets validate check-systemd check-python

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

check-contracts:
	bash scripts/ci/check-shell-contracts.sh

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

validate:
	bash scripts/ci/validate-generated-config.sh

generate:
	bash scripts/generate/generate-settings.sh
	bash scripts/generate/generate-compositor-modules.sh
	bash scripts/generate/generate-workspaces-css.sh
