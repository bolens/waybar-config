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
