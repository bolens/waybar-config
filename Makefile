# Waybar config — local developer tasks
#
# Usage: make check | make generate | make check-syntax

WAYBAR_HOME ?= $(CURDIR)
WAYBAR_SCRIPTS ?= $(WAYBAR_HOME)/scripts
export WAYBAR_HOME WAYBAR_SCRIPTS

.PHONY: check check-syntax check-contracts check-generator check-secrets validate generate help

help:
	@printf '%s\n' \
		'make check          - contracts + generator tests (incl. secrets) + validate' \
		'make check-syntax   - bash -n on all scripts/**/*.sh' \
		'make check-contracts' \
		'make check-generator' \
		'make check-secrets' \
		'make validate' \
		'make generate       - regenerate settings/modules/css from data/'

check: check-contracts check-generator validate

check-syntax:
	@set -euo pipefail; \
	fail=0; \
	while IFS= read -r f; do \
		echo "Checking $$f"; \
		bash -n "$$f" || fail=1; \
	done < <(find scripts -type f -name '*.sh' | sort); \
	exit $$fail

check-contracts:
	bash scripts/ci/check-shell-contracts.sh

check-generator:
	bash scripts/ci/run-generator-tests.sh

check-secrets:
	bash scripts/ci/run-secrets-and-settings-tests.sh

validate:
	bash scripts/ci/validate-generated-config.sh

generate:
	bash scripts/generate/generate-settings.sh
	bash scripts/generate/generate-compositor-modules.sh
	bash scripts/generate/generate-workspaces-css.sh
