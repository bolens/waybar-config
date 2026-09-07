# Feature specification: Generated Waybar settings and module adapters

**Created**: 2026-09-05
**Status**: Retrospective baseline
**Inspected revision**: `8fea3db079d2f8cab4a8f98598131df7a05516b9`
**Input**: The owner requested a fleet-wide Spec Kit retrofit and implementation audit.

Declarative JSONC owns generated bar configuration, CSS, and optional service adapters; private overlays remain separate from shared source.

This specification records existing contracts after implementation. It does not
claim that the original work followed Spec Kit. New behavior requires a separate
change contract. Existing feature specifications remain authoritative within their
own scope.

## User scenarios and testing

### User story 1: Use documented source (P1)

A maintainer selects the supported source or entry point.

**Acceptance**: Behavior and outputs match the requirement mapping below.

### User story 2: Handle boundary cases (P2)

Inputs are invalid or optional content is missing.

**Acceptance**: Named source checks preserve explicit failure or fallback behavior.

### User story 3: Maintain the contract (P3)

A future change affects this baseline.

**Acceptance**: Revise the owning source, documentation, and acceptance evidence together.

## Requirements

- **FR-001**: Editable settings and generators MUST remain the source of compiled JSONC/CSS output.
- **FR-002**: Generator wiring, module behavior, cache and fallback contracts MUST retain their existing per-module acceptance fixtures.
- **FR-003**: Private settings overlays MUST retain their documented merge, redaction, and file policy without leaking values through MCP status.
- **FR-004**: CoolerControl password handoff MUST satisfy the existing stdin-only feature specification and retain token/fallback/cookie cleanup behavior.
- **FR-005**: Source, generated artifacts, documentation index, schema checks, and CI suite selection MUST remain consistent.

## Corrective requirements from the detailed legacy audit

Inspected revision: `cf333de` (2026-09-06). These are new corrections, not claims
about the behavior of the historical baseline.

- **FR-006**: MCP tool calls MUST validate declared argument types, required fields, enum values and array element types before invoking a handler. In particular, string or numeric confirmation values MUST NOT authorize restart or overwrite, and invalid write arguments MUST preserve settings bytes.
- **FR-007**: Invalid JSON-RPC/MCP requests MUST produce a protocol error response when a response is required, and the stream MUST remain usable for later requests. Notifications MUST NOT receive responses.
- **FR-008**: MCP settings reads MUST redact secret-looking keys before selecting a dotted path, including reads selecting a single secret value.
- **FR-009**: Restoring malformed JSONC or a non-object backup MUST fail before changing either the source or compiled settings. This requirement does not promise a transaction across both files after validation succeeds.
- **FR-010**: Both shared JSONC comment strippers MUST preserve quoted strings, escaped quotes and backslashes, including comment delimiters inside values. Removing comments MUST preserve separation between JSON tokens.
- **FR-011**: Redaction MUST replace a secret-key value even when it is an object or array. The settings patch and dotted-path write guards MUST reject secret-looking keys nested inside supplied objects or arrays before writing.
- **FR-012**: The interval setter MUST reject JSON booleans as integer intervals.
- **FR-013**: Client registration MUST preserve unreadable, malformed or structurally invalid existing configuration, retain unrelated entries in valid configurations, and return failure if any attempted registration fails. Independent valid client configurations MAY still be updated.
- **FR-014**: Prompt requests MUST enforce declared required arguments and string argument values, reporting invalid parameters instead of rendering an incomplete workflow.

## Success criteria

- **SC-001**: Every requirement has a named source owner and acceptance check in `coverage.md`.
- **SC-002**: The listed native checks pass for the reviewed candidate, with unavailable environments and operational checks recorded separately.
- **SC-003**: Retrofitting preserves existing interfaces and completed specifications. Any confirmed implementation gap is corrected under an explicit requirement before it is marked complete.

## Edge cases and operational limits

Portable source fixtures do not prove live KDE/Hyprland/Waybar behavior or hardware integrations. Existing password transport scope excludes a redesign of bearer headers, cookie storage, and configured secret overlays; those policies remain separate. No desktop application, credential rotation, or service mutation occurred.

- **FR-015**: Generated network status and click commands MUST pass each manifest interface name as one literal shell argument, including names containing shell metacharacters.

[Generator contracts](legacy-generators.md) map all 24 generator entry points
and record their remaining acceptance boundaries.

- **FR-016**: Dock generation MUST reject malformed manifests and IDs outside `[A-Za-z0-9_-]+` before replacing its outputs. Drawer class strings MUST be JSON-encoded.
- **FR-017**: Explicit false dock drawer click-to-reveal and direction settings MUST survive generation.

- **FR-018**: Theme preset loading MUST preserve quoted comment delimiters and accept JSONC comments using the shared parser before applying color overrides.

- **FR-019**: Shared desktop icon maps MUST parse valid desktop entries and retain class, name and executable mappings after a warm cache load returns to its caller. Existing cache declarations MUST remain readable.

- **FR-020**: The animation wrapper MUST preserve the child command exit status after collecting its output and removing owned temporary files, so callers can select fallback providers.

- **FR-021**: CPU and memory process-list caches MUST encode process names as JSON strings, preserving literal backslashes and quotes so a process label cannot break the shared metrics JSON.

- **FR-022**: The shared brightness library MUST load its settings and output helpers from the selected scripts root in Bash and POSIX sh, with or without an explicit `WAYBAR_SCRIPTS`. Disabled per-output settings MUST retain the shared cache path.

- **FR-023**: Concurrent KDE listener JSON cache writes MUST use distinct owned temporary files and publish complete JSON through replacement. Failed replacement MUST preserve the destination and remove the failed writer's temporary file.

- **FR-024**: Tailscale status parsing MUST preserve empty optional fields without shifting peer counts, exit-node text or health messages. Health warnings MUST remain visible when no IPv4 or exit node is present.

- **FR-025**: Network interface status refresh MUST collect manifest interface names and use the manifest bond interface for hiding subordinate modules. Cached reads MUST retain configured interfaces instead of replacing them with hard-coded machine names. Without a manifest, legacy defaults remain supported.

- **FR-026**: VPN summary matching MUST NOT count `Disconnected` as `Connected` for Netbird or Mullvad. Only complete connection-state words may contribute to the active tunnel count.

- **FR-027**: A failed full-screen capture in the Hyprland/grimblast path MUST return the capture failure and MUST NOT copy an image or announce a saved screenshot. This applies with and without output targeting.

- **FR-028**: Microphone toggle MUST report failure when mute control fails or the subsequent volume query is empty, rather than announce a live or muted state it could not confirm. Refresh signaling may still invalidate stale status.
