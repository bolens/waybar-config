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

[Runtime contracts](legacy-runtime.md) record the inspected shared helpers and weather entry point. Unread runtime/listener source remains explicitly pending.

FR-023 maps to the shared KDE listener JSON writer. A synchronized two-thread fixture reproduced reuse of one PID-named temporary path. Unique temporary files now allow both complete replacements; an injected replacement failure preserves the previous destination and leaves no temporary file. The full shared-library suite passes with stub GI and no D-Bus calls.

FR-024 maps to `tailscale-status.sh` and the existing `vpn-cooling-refresh` suite. A stub response with absent IPv4/exit node previously shifted peer count and health text into the wrong fields; JSON indexing now preserves the health warning and empty values.

FR-025 maps to `network-interface-status.sh` and the existing network suite. A custom manifest fixture previously refreshed only hard-coded interfaces and used the host bond name. Refresh now uses configured interface/bond names, and subsequent cached reads retain the configured interface. Command dependencies are stubbed.

FR-026 maps to `vpn-status.sh` and the VPN suite. Stubbed disconnected Netbird and Mullvad reports previously yielded two active tunnels; whole-word matching now reports zero, while connected reports retain two. Every VPN command is stubbed. CI exposed a missing-ripgrep path that reported Netbird inactive; provider matching now uses grep, and the fixture makes ripgrep unavailable while checking ZeroTier OFFLINE/ONLINE alongside those providers.

FR-027 maps to `screenshot-click.sh` and `lib-utils`. Stub capture failure previously returned success and announced a saved file. Both targeted and untargeted full-screen cases now retain exit 7 and perform no clipboard or notification action.

FR-028 maps to `mic-toggle.sh` and `lib-utils`. Stub control failure previously announced LIVE and returned success. Failure now produces an unavailable/control-error message and nonzero status, while refresh signaling remains permitted. No microphone was accessed.

### Network popup and listener corrections

- FR-029: `vpn-status-popup.py` returned incomplete fallback fields. The complete
  UI raised `KeyError('ipv4')` with unavailable providers. The corrected fallback
  passes the stubbed GTK UI, including the details toggle.
- FR-030: Ethernet connection names containing `&` and `<` produced invalid label
  markup. Presentation escaping now covers both popups and sensitive reveal.
  The Ethernet fixture checks DNS masking in both states. No network tool or
  graphical session is used by these function-body fixtures.
- FR-031: An immediately failing zscroll restarted 111 times in 250 ms in a
  disposable process group. The corrected wrapper waits before retrying. The
  regression intercepts the wait and checks launch/wait order without timing
  assumptions or a real media player.
- FR-032: An owned listener process released its lock on SIGTERM but kept running.
  Bash and dash regressions now verify exit status 143 and lock removal. The
  fixtures use private runtime directories and signal only their child processes.

Before these four corrections, commit `3cc7a5d085e62887c43f613cea72fab08b013a10`
passed all 52 generator and nine secrets suites, check-fast, generated drift,
Ruff and the native Gitleaks check. Two GTK probes were skipped by that Python
runtime. These results remain evidence for that commit, not the later candidate.

After FR-029 through FR-032, all three affected suites passed in full, as did the
shared Bash/dash shell-contract gate, Ruff, ShellCheck, shfmt and Markdown lint.
The system Python ran both previously skipped GTK probes and the full-file CSS
parser successfully. Separate self-review traced fallback fields, presentation
escaping, retry control flow and the five listener consumers. Pipeline descendant
cleanup remains an explicit audit item. No independent reviewer was used.
