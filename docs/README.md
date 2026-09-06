# Documentation

Waybar settings generation, optional modules, and local state.

## Start here

| Need | Owning document |
| --- | --- |
| Use the project | [README.md](../README.md) |
| Change the repository | [AGENTS.md](../AGENTS.md) |
| Deliver or recover | [RELEASING.md](../RELEASING.md) |
| Plan substantial changes | [.specify/memory/project-guide.md](../.specify/memory/project-guide.md) |
| Non-negotiable constraints | [.specify/memory/constitution.md](../.specify/memory/constitution.md) |

## Architecture

[Architecture](architecture.md) owns the settings-to-generation-to-Waybar flow. [Editable
JSONC](../data/waybar-settings.jsonc) is authoritative. Generated JSONC/CSS and compiled settings
must not become independent sources. Module cache, signals, and compositor behavior follow shared
contracts.

## Deployment and recovery

[README](../README.md) owns installation and systemd operation. [RELEASING.md](../RELEASING.md) owns
source delivery and recovery. Generation does not reload the running bar. Missing optional
dependencies should hide or degrade a module without breaking the rest of the bar.

## Database and state

There is no database server. Editable settings, compiled output, module caches, and the private
secrets overlay have separate owners. [Settings reference](settings-reference.md) owns configuration
and [MCP](mcp.md) documents writes, including JSONC comment loss. Never commit runtime secrets or
substitute caches for settings.

## Documentation maintenance

Keep decisions, invariants, failure modes, and recovery requirements in the owning document. Link to
commands, defaults, schemas, and generated catalogs instead of copying them. Change the owner and
affected references together. Update this index when adding or moving a guide, and verify relative
links and heading anchors. Historical specs and audits describe their recorded revision, not current
runtime proof. A topic without an implementation stays explicitly unimplemented.

## Topic guides

Canonical map of project docs. **When you add or rename a doc, update this file** (CI enforces
`docs/*.md` coverage).

| Doc | Topic |
|-----|--------|
| [../README.md](../README.md) | User-facing hub (install, modules, dependencies) |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Setup, checks, secrets, PR norms |
| [../AGENTS.md](../AGENTS.md) | Short briefing for AI coding agents |
| [architecture.md](architecture.md) | Settings → generate → Waybar pipeline |
| [settings-reference.md](settings-reference.md) | Top-level keys in `waybar-settings.jsonc` |
| [adding-a-module.md](adding-a-module.md) | Checklist for new status modules |
| [theming.md](theming.md) | Presets, wallpaper, floating, reduced motion |
| [troubleshooting.md](troubleshooting.md) | Common failures and fixes |
| [mcp.md](mcp.md) | Optional MCP server for AI assistants |
| [../scripts/README.md](../scripts/README.md) | Script layout, growth rules, CI harness |

## Suggested reading order

1. [architecture.md](architecture.md) — how the tree fits together  
2. [settings-reference.md](settings-reference.md) — what to edit  
3. [adding-a-module.md](adding-a-module.md) or [theming.md](theming.md) — task-specific  
4. [CONTRIBUTING.md](../CONTRIBUTING.md) — before opening a PR  
5. [troubleshooting.md](troubleshooting.md) — when something breaks  
6. [AGENTS.md](../AGENTS.md) / [mcp.md](mcp.md) — agent workflows  

## Maintaining this index

- New file under `docs/` → add a row here and a one-line hub link at the top of that file (`> Doc map: [Documentation index](README.md)`).
- Root briefs (`README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `scripts/README.md`) should link back here.
- `make check-docs-index` (also in `make check` / `check-fast` and the Markdownlint workflow) fails if a `docs/*.md` page (except this README) is missing from the table, or if hub backlinks are missing.
