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

When you add `scripts/ci/tests/generator/foo.sh` or `secrets/foo.sh`, add `foo` to the matching matrix in [`.github/workflows/ci.yml`](.github/workflows/ci.yml). Shared libs touched by secrets suites may also need a dorny `secrets:` path entry (see existing `scripts/lib/*` lines). Signal registry / keyed refresh coverage lives in `module-signals`. Tooltip Pango / `escape` double-escape regressions live in `tooltip-pango-escape`. Overlay net modules (Yggdrasil / IPFS) live in `overlay-network-modules`.

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
- Route every change through a pull request, including maintainer changes.
- Wait for required checks and resolved conversations, then squash-merge and
  delete the branch. Do not push directly to `main` or bypass protection.

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

## Woodpecker CI

### CI organization

The [shared purpose phases](https://github.com/bolens/.github/blob/main/docs/woodpecker-transition.md#ci-organization)
index the existing Nix and Make targets. `devenv test` runs the complete locked
Linux development gate; focused targets below expose its component groups.

| Phase | Check group / canonical local command | Native workflow / step | Retained hosted owner / boundary |
| --- | --- | --- | --- |
| `validate` | Complete Linux source/configuration gate: `devenv test`; quick local iteration: `make check-fast` | `woodpecker` / `verify` | PR, main push, native manual and configured main cron execution |
| `test` | Generator and secret fixtures: `make check-generator check-secrets` | Included in the same locked Linux gate | Disposable settings, processes and secret overlays; no live desktop restart |
| `validate` | Generated drift and inventory: `make check-drift check-suite-inventory check-docs-index` | Included in the same locked Linux gate | Source/generator changes retain their existing regeneration and suite-selection requirements |
| `validate` | Managed integration: `devenv shell -- bash scripts/check-spec-kit.sh` | `woodpecker` / `verify` | Same locked tooling shell and existing validator pin |
| `test` | Development images: existing commands in the [development guide](docs/development-environments.md) | Separate hosted acceptance | Native macOS and actual Docker/editor-image checks keep their existing selection |

The native alias, required statuses, weekly selector and retained hosted owners
remain stable. Reviewed source delivery and live Waybar application keep their
separate authority; no CI group authorizes a restart or live secret write.

[.woodpecker.yml](.woodpecker.yml) validates the canonical GitHub source and
reconciled Gitea copies on main pushes, pull requests, manual builds and configured
main cron runs. Either Linux Docker runner can execute the workflow; container
images are pinned by digest.

The workflow runs the full locked Linux Nix development gate and Spec Kit
validation, including generator and secret-fixture suites, generated-artifact
drift, GTK CSS parsing and source/workflow policy. Tests use disposable
configuration and secret fixtures. They do not restart Waybar or change a desktop
session. See [native Linux validation](docs/development-environments.md#woodpecker-linux-validation)
for the commands and isolation contract.

GitHub Actions retain native macOS, actual Docker/devcontainer checks, assignment
and the Spec Kit updater. GitHub-managed CodeQL also remains on GitHub. Keep
every active required check green on the current PR head; follow [delivery and retirement](RELEASING.md#woodpecker-migration) for
native PR/main/weekly-cron proof, required-check migration and rollback. Review
image digest updates alongside the repository toolchain and lockfiles.

## Devcontainer

See [the devcontainer guide](.devcontainer/README.md) for the repository toolchain,
setup, checks and platform limits.

## Native Woodpecker checks

Run `devenv test`, then `devenv shell -- bash scripts/check-spec-kit.sh` to
reproduce the native Linux pipeline. See
[development environments](docs/development-environments.md#woodpecker-linux-validation)
for tool ownership and hosted platform exceptions. During migration, require the
existing GitHub checks as well as the observed native result; never infer a
protection change from a workflow edit.
