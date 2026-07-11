# Waybar config — local developer tasks
#
# Usage: make check | make generate | make check-syntax

WAYBAR_HOME ?= $(CURDIR)
WAYBAR_SCRIPTS ?= $(WAYBAR_HOME)/scripts
export WAYBAR_HOME WAYBAR_SCRIPTS

.PHONY: check check-syntax check-python check-contracts check-generator check-secrets check-systemd validate generate help

help:
	@printf '%s\n' \
		'make check          - syntax + contracts + generator (incl. secrets) + validate + systemd + python' \
		'make check-syntax   - bash -n on all scripts/**/*.sh' \
		'make check-python   - python3 -m py_compile on scripts/**/*.py' \
		'make check-contracts' \
		'make check-generator' \
		'make check-secrets' \
		'make check-systemd  - systemd unit templates point at real scripts' \
		'make validate' \
		'make generate       - regenerate settings/modules/css from data/'

# Generator tests already embed secrets/settings exposure tests.
check: check-syntax check-contracts check-generator validate check-systemd check-python

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
	bash scripts/ci/run-generator-tests.sh

check-secrets:
	bash scripts/ci/run-secrets-and-settings-tests.sh

check-systemd:
	bash scripts/ci/check-systemd-units.sh

validate:
	bash scripts/ci/validate-generated-config.sh

generate:
	bash scripts/generate/generate-settings.sh
	bash scripts/generate/generate-compositor-modules.sh
	bash scripts/generate/generate-workspaces-css.sh
