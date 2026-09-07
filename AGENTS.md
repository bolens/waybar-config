# Agent guidance

Read [.specify/memory/constitution.md](.specify/memory/constitution.md) and use [docs/README.md](docs/README.md) as the document
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

## Planning and evidence

Use the [project guide](.specify/memory/project-guide.md) and
[constitution](.specify/memory/constitution.md) for substantial changes. The guide
owns Spec Kit scope, retained history, retrospective requirements, and acceptance
evidence. Prose maintenance uses the normal repository workflow.

## Context and handoffs

- Search before reading. Use bounded source excerpts for exploratory reads over
  350 lines, and inspect required guidance and actual source before editing.
- When delegation is permitted, assign a bounded question or output, paths, and
  check. Return source locations, changes, and verification gaps for final review.
- Keep durable corrections in the [project guide](.specify/memory/project-guide.md)
  or owning contract. Replace superseded advice and read it before reuse.
  Temporary progress belongs in task notes. Preserve existing authority rules.
