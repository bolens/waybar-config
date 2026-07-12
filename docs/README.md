# Documentation index

Canonical map of project docs. **When you add or rename a doc, update this file** (CI enforces `docs/*.md` coverage).

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
