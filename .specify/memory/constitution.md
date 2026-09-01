# Waybar Configuration Constitution

## Core Principles

### I. Declarative Settings Source
`data/waybar-settings.jsonc` and generators are authoritative. Generated JSONC, CSS, and compiled settings MUST not be hand-edited and MUST remain reproducible.

### II. Secret and Local-State Isolation
Secrets belong only in the ignored, permission-restricted overlay. Generators, tests, MCP, logs, and committed examples MUST not expose live values or depend on personal runtime state.

### III. Graceful Optional Modules
Modules MUST hide or degrade cleanly when optional dependencies, hardware, sessions, or services are absent. Shared cache, signal, tooltip, and compositor contracts remain centralized.

### IV. Explicit Operational Actions
Generation and validation are repository actions; restarting Waybar, changing live settings, installing tools, or writing secrets are operational actions requiring explicit confirmation.

### V. Generated Drift and Suite Coverage
Source changes MUST regenerate intended artifacts and pass drift checks. New generator/secrets suites require matching CI matrix and path-filter coverage; indexed docs change with behavior.

## Governance

`docs/README.md` maps detailed sources of truth. Exceptions to generation or secret boundaries require explicit approval and a version update.

**Version**: 1.0.0 | **Ratified**: 2026-08-15 | **Last Amended**: 2026-08-15
