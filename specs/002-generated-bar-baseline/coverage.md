# Requirement coverage

| Requirement | Source and acceptance evidence |
| --- | --- |
| FR-001 | data/waybar-settings.jsonc, scripts/generate, canonical drift checks and generator fixture suites. |
| FR-002 | scripts/ci/tests/generator, check-contracts and CI suite-inventory checks; no claim of live desktop validation. |
| FR-003 | scripts/mcp/secrets_ops.py, structure_only, and scripts/ci/tests/secrets fixtures. |
| FR-004 | specs/001-coolercontrol-password-stdin and both isolated authentication suites, exercised by make check. |
| FR-005 | Makefile check-suite-inventory/check-docs-index/check-drift and native syntax/style checks. |

## Verification receipt

The full make check gate passed with locked lint dependencies: generator and secrets fixtures, syntax/contracts, CI suite inventory, docs index, regeneration drift, systemd source checks, Ruff/shfmt, gitleaks, and CSS/Markdown validation. Separate self-review traced settings output ownership, private-overlay metadata, and the existing stdin password/cookie cleanup contract. GTK3 runtime probing remains unavailable locally; no Waybar restart or live secret-overlay read was performed.

## Detailed audit in progress: 2026-09-06

[Legacy MCP contracts](legacy-mcp.md) map 48 tools, transport, resources and
prompts to source and evidence limits. FR-006 through FR-009 and FR-011/FR-012
have focused MCP regressions. FR-010 and structured redaction have native
shared-parser fixtures in `lib-utils.sh`. Focused checks pass; the full candidate
gate remains pending. The earlier receipt belongs to the original baseline.

FR-015 maps to network generator shell quoting and the existing
`overlay-network-modules` suite. Ten status/click commands preserve interface
arguments literally; native interface and tooltip values remain unchanged.
The full suite passes with disposable command stubs.

FR-016/FR-017 map to `drawer-sot-contracts`, whose focused boundary and full
suite pass. FR-018 maps to `lib-utils`, whose full suite passes. All generator
scripts have source contracts. Native generator and secrets suites passed
except a sandbox-only CoolerControl socket denial, resolved by an isolated
loopback rerun. Source syntax, Ruff, shfmt, generated-config validation, systemd
templates, sensitive-pattern gate, direct pinned-version CSS/Markdown lint and
GTK3 full CSS parsing pass. Generated drift and remaining runtime audit are
not yet complete. pnpm could not use its default local database; direct linter
executables used the same installed dependency versions and arguments.

FR-019 maps to `xdg-icons-lib.sh` and the existing `lib-utils` suite. A disposable desktop entry failed cold parsing before moving the AWK function to top level, then failed warm loading before promoting cached map declarations to global scope. Both cases and the full suite now pass. Window switcher and notification-menu consumers retain their existing lookup interface.

FR-020 maps to `unicode-animations-lib.sh`. Its disposable child-command fixture verifies status 7 and temporary cleanup. The weather suite exercises the real animation wrapper with stubbed HTTP, requiring wttr.in after Open-Meteo fails. Existing GitHub and shared-library suites also pass.

FR-021 maps to `system-metrics-top.sh` and `lib-utils`. A stub process name containing a backslash and quote produced invalid JSON before the correction. Native jq string encoding now preserves the CPU and memory labels consumed by the collector.

FR-022 maps to `brightness-lib.sh` and its existing shared-library suite. Removing the stray path brace allows default and explicit script roots to load. The fixture verifies disabled per-output cache selection in Bash and sh; a separate local dash run passes. No device probing or brightness change is performed.
