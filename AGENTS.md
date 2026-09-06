# Agent guidance

Before Spec Kit planning or implementation, read
`.specify/memory/project-guide.md` with the project constitution. It maps
requirements to this repository's source, acceptance evidence, and validation.

Read `.specify/memory/constitution.md` and use `docs/README.md` as the document
map. The editable settings source is `data/waybar-settings.jsonc`.

- Never hand-edit `*.generated.jsonc`, `*.generated.css`, or compiled
  `data/waybar-settings.json`; change settings/generators and run
  `make generate`.
- Keep secrets only in gitignored `data/waybar-secrets.jsonc` with mode `0600`.
  Never expose or write live secret values through MCP.
- Optional modules must hide cleanly when dependencies are absent. Use the
  signal registry helper rather than hard-coded real-time signal numbers.
- Settings writes through MCP rewrite JSONC and lose comments; disclose this
  before using them. Restarting Waybar is an operational action and requires
  explicit confirmation.
- Add CI suite/matrix and path-filter coverage when adding generator or secrets
  tests. Update the documentation index when docs move or are added.
- Run `make generate` after source changes, then the narrow relevant suite or
  `make check-fast`; use `make check` for cross-cutting work. Include intended
  generated diffs and report skipped optional tools.

## Spec-driven changes

Use Spec Kit for new capabilities, architecture, security-sensitive behavior,
migrations, and coordinated multi-file changes. Keep narrow fixes, dependency
updates, prose edits, and release housekeeping in the normal repository
workflow unless their risk warrants a written specification. Keep completed
feature directories under `specs/` as decision history; do not backfill them for
finished work.

## Context and handoffs

- Locate source with targeted searches before reading. For exploratory reads of
  files over 350 lines, select relevant ranges. Read required guidance and actual
  source before edits or correctness claims; summaries do not replace them.
- When delegation is permitted, give each worker one question or concrete output,
  allowed paths, and a check. Return findings with source locations, changed paths,
  and verification gaps. Keep final review with the coordinating agent.
- Record durable user corrections in the [project guide](.specify/memory/project-guide.md)
  or owning contract with scope, reason, and evidence. Replace superseded advice;
  read relevant corrections before reusing assumptions. Keep temporary progress
  in task notes and preserve existing authority rules.
