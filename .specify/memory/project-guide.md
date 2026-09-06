# waybar-config Spec Kit project guide

Declarative Waybar settings, generated configuration/CSS, and optional module adapters.

Read this guide with `AGENTS.md` and `.specify/memory/constitution.md` before
specifying, planning, or implementing a substantial change. It is project-owned
guidance, not an upstream-managed template.

## Source and ownership map

- `data/waybar-settings.jsonc`
- `scripts/`
- `modules/`
- `theme/`
- `docs/README.md`
- `Makefile`

## Specification and plan decisions

Locate the editable setting or generator and its module/cache/signal contract. Keep
source and generated outputs distinct. Plan schema, defaults, settings UI/MCP, docs,
generated files, and test inventory together when a setting changes.

## Acceptance evidence

Cover absent optional commands, malformed data, cache expiry, timing boundaries,
platform-specific fallbacks, secret redaction, and regeneration without drift. Use the
existing isolated harness and ensure new suites are selected by CI.

## Validation and operational limits

```sh
make check-fast
make check
```

Run make generate after source changes and inspect generated diffs. Do not edit compiled
settings or generated CSS/JSONC directly. Do not restart Waybar, write the live secret
overlay, or use the running desktop as a test fixture.

## Working through Spec Kit

Use Spec Kit for new capabilities, architectural or security-sensitive changes,
migrations, and coordinated changes that need a written contract. Keep narrow fixes,
dependency updates, and prose maintenance in the normal PR workflow.

For a new feature, record observable acceptance criteria in `spec.md`, source ownership
and constitution checks in `plan.md`, and evidence-bearing work in `tasks.md` under the
feature directory created by Spec Kit. Resolve material unknowns before implementation.
Mark tasks complete only after their stated verification, and distinguish completed,
skipped, blocked, and manual checks. Retain completed feature documents as decision
history. Backfill finished work only when explicitly requested. Label those
specifications as retrospective baselines, record the inspected revision, and map
requirements to source and acceptance evidence. Separate observed behavior from
corrective requirements. Never imply the specification preceded its code or mark
unverified checks complete.

Keep `.specify/templates/`, `.specify/scripts/`, and generated Codex skills under their
integration manifests. Use this guide and the constitution for local customization.
Regenerate managed files through Spec Kit and verify that project-owned memory survives
updates. Follow `RELEASING.md` for push, merge, release or delivery, and recovery.

The retrospective specification register is [specs/README.md](../../specs/README.md).
