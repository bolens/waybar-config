# Agent briefing (Waybar config)

> Doc map: [Documentation index](docs/README.md) · [Contributing](CONTRIBUTING.md) · [MCP](docs/mcp.md)

Short rules for AI coding agents working in this repository.

## Source of truth

- Edit **`data/waybar-settings.jsonc`** (and scripts / generators).
- **Never** hand-edit `*.generated.jsonc` or `*.generated.css`.
- `data/waybar-settings.json` is a compiled artifact and will be overwritten.
- Secrets belong only in **`data/waybar-secrets.jsonc`** (gitignored, mode `0600`). Never commit secrets or put passwords in the main settings file.

## Pipeline

```text
settings.jsonc → make generate → modules/layouts/theme generated artifacts → Waybar
```

After settings or generator changes: `make generate`, then validate. Prefer `systemctl --user restart waybar` to reload.

Details: [docs/architecture.md](docs/architecture.md).

## Prefer existing tooling

| Task | Use |
|------|-----|
| Find any doc | [docs/README.md](docs/README.md) (canonical index) |
| Inspect / patch settings as an MCP client | [docs/mcp.md](docs/mcp.md) — `scripts/mcp/waybar-mcp.py` |
| Add a status module | [docs/adding-a-module.md](docs/adding-a-module.md) |
| Theme / presets / wallpaper | [docs/theming.md](docs/theming.md) |
| Key meanings | [docs/settings-reference.md](docs/settings-reference.md) |
| Something broken | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Signal a module after click/listener work | `scripts/lib/waybar-signal.sh <signals.* key>` (prefer key, not RTMIN number) |
| Local gate | `make check-fast` or targeted `scripts/ci/tests/…` |
| Contributor norms | [CONTRIBUTING.md](CONTRIBUTING.md) |

## Do / don’t

- **Do** keep PRs small; regenerate and commit intended generated artifacts.
- **Do** hide modules when optional deps are missing.
- **Do** add CI suite + matrix entry when adding generator/secrets tests (`make check-suite-inventory`).
- **Do** refresh modules with `waybar-signal.sh <key>` matching `signals.*` / generated `signal`.
- **Don’t** reimplement generators in ad-hoc Python when `make generate` already covers the path.
- **Don’t** write live secrets via MCP or dump secret values into chat/logs.
- **Don’t** skip hooks or force-push `main`.
- **Don’t** hardcode `pkill -RTMIN+N` in new click/listener code.

## MCP quick flow

`waybar_backup_settings` → edit tools → `waybar_generate` → `waybar_validate` → `waybar_restart` with `confirm=true`.

Programmatic settings writes rewrite pretty JSON (**JSONC comments are lost**).

## Related docs

Full map: [Documentation index](docs/README.md).

| Doc | Topic |
|-----|--------|
| [Architecture](docs/architecture.md) | Pipeline |
| [Settings reference](docs/settings-reference.md) | Keys |
| [Adding a module](docs/adding-a-module.md) | New modules |
| [Theming](docs/theming.md) | Themes |
| [Troubleshooting](docs/troubleshooting.md) | Failures |
| [MCP](docs/mcp.md) | Tool/resource/prompt tables |
| [Contributing](CONTRIBUTING.md) | Checks / PRs |
| [Scripts layout](scripts/README.md) | Domains + CI |
