# Contributing

> Doc map: [Documentation index](docs/README.md) · [Root README](README.md) · [AGENTS.md](AGENTS.md)

Thanks for improving this Waybar config. Keep changes focused, regenerate artifacts, and do not commit secrets.

## Setup

```bash
git clone https://github.com/bolens/waybar-config.git ~/.config/waybar
cd ~/.config/waybar
cp -n data/waybar-secrets.example.jsonc data/waybar-secrets.jsonc
chmod 600 data/waybar-secrets.jsonc
make generate
make install-hooks    # blocks accidental secret commits
```

Optional: enable systemd user units as described in the [README](README.md#installation).

## Development loop

1. Edit **`data/waybar-settings.jsonc`** (or scripts / generators) — never hand-edit `*.generated.jsonc` / `*.generated.css`.
2. `make generate`
3. Run a relevant suite or `make check-fast` / `make check`
4. Reload: `systemctl --user restart waybar` (or MCP `waybar_restart` with `confirm=true`)

See [architecture](docs/architecture.md), [settings reference](docs/settings-reference.md), and [adding a module](docs/adding-a-module.md).

## Checks

```bash
make check-fast      # quick local gate
make check           # full gate (suites + drift + lint)
make check-generator # all generator suites
make check-secrets   # secrets/settings suites
make check-suite-inventory  # CI matrix ↔ on-disk suites + CSS path-filter coverage
make check-docs-index       # docs/README.md ↔ docs/*.md + hub backlinks
make check-drift     # generate then fail on dirty generated files
```

Single suite:

```bash
bash scripts/ci/tests/generator/mcp-server.sh
bash scripts/ci/tests/secrets/i2pd-sync.sh
```

Harness docs: [`scripts/README.md`](scripts/README.md#ci-test-layout).

When you add `scripts/ci/tests/generator/foo.sh` or `secrets/foo.sh`, add `foo` to the matching matrix in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Secrets

| Do | Don't |
|----|--------|
| Keep secrets in `data/waybar-secrets.jsonc` mode `0600` | Commit secrets or paste them into PRs |
| Copy from `waybar-secrets.example.jsonc` | Put passwords in `waybar-settings.jsonc` |
| Use `make install-hooks` | Rely on `.gitignore` alone |

Helpers: `scripts/services/i2pd/i2pd-set-console-pass.sh`, `scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh` (often need `sudo`).

## Profiles

```bash
make profile-minimal   # merge data/profiles/minimal-groups.jsonc + generate
```

Deep-merge rewrites the settings JSONC (comments in the base file are not preserved).

## AI / MCP

Optional agent API: [docs/mcp.md](docs/mcp.md). Agent briefing: [AGENTS.md](AGENTS.md).

## Style

- Shell: existing patterns under `scripts/`; `make fmt-shell` / ShellCheck (warning severity).
- Python: stdlib preferred for helpers; `ruff` on `scripts/`.
- Docs: keep README as the user-facing hub; deeper topics live under `docs/`. **When adding or renaming a doc, update [docs/README.md](docs/README.md)** (enforced by `make check-docs-index`).

## PRs

- Prefer small, reviewable PRs.
- Include regenerated artifacts when generators change.
- Note new optional dependencies in the README Dependencies section.
- Do not force-push to `main` or skip hooks unless explicitly required and agreed.

## Related docs

Full map: [Documentation index](docs/README.md).

| Doc | Topic |
|-----|--------|
| [Architecture](docs/architecture.md) | Pipeline |
| [Settings reference](docs/settings-reference.md) | Settings keys |
| [Adding a module](docs/adding-a-module.md) | Module checklist |
| [Theming](docs/theming.md) | Themes |
| [Troubleshooting](docs/troubleshooting.md) | Failures |
| [MCP](docs/mcp.md) | Agent API |
| [AGENTS.md](AGENTS.md) | Agent briefing |
| [Scripts layout](scripts/README.md) | CI harness |
