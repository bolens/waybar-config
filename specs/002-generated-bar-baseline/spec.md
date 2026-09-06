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

## Success criteria

- **SC-001**: Every requirement has a named source owner and acceptance check in `coverage.md`.
- **SC-002**: The listed native checks pass for the reviewed candidate, with unavailable environments and operational checks recorded separately.
- **SC-003**: Retrofitting preserves existing interfaces and completed specifications. Any confirmed implementation gap is corrected under an explicit requirement before it is marked complete.

## Edge cases and operational limits

Portable source fixtures do not prove live KDE/Hyprland/Waybar behavior or hardware integrations. Existing password transport scope excludes a redesign of bearer headers, cookie storage, and configured secret overlays; those policies remain separate. No desktop application, credential rotation, or service mutation occurred.
