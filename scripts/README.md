# Scripts layout

Scripts are grouped so related status/click/popup pairs stay together, with shared infrastructure in top-level folders.

| Folder | Purpose |
|--------|---------|
| `lib/` | Shared helpers (`waybar-settings`, cache helpers, `app-open-lib`, `*-lib`, compositor helpers, signals) |
| `generate/` | Config generators (`generate-*.sh`) |
| `ci/` | Contract checks, unit tests, validate, pre-commit hook |
| `infra/` | Launch, healthcheck, listener-ctl, metrics collector |
| `listeners/` | Long-running watchers |
| `dock/` | Dock launcher + dock-windows |
| `workspaces/` | Workspaces, active window, keybind hints |
| `system/` | CPU/mem/disk/gpu/nvme/fans/liquidctl/asusctl/rgb/power/brightness/… |
| `network/` | Wi‑Fi, VPN, ethernet, Tailscale, … |
| `media/` | Audio, mic, MPRIS |
| `notifications/` | Notifications + clipboard |
| `capture/` | Screenshot / screenrecord / color picker |
| `services/` | Third-party integrations (see subfolders below) |
| `tools/` | Small UX helpers (`app-open`, `calendar-popup`) |

### `services/` subfolders

| Subfolder | Examples |
|-----------|----------|
| `security/` | privacy, vaults, libredefender, chkrootkit |
| `devices/` | device-notifier, kdeconnect, streamdeck, device-battery |
| `apps/` | discord, github, weather, sunshine |
| `containers/` | docker, runtimes |
| `sync/` | updates, syncthing |
| `i2pd/` | i2pd status + console-pass helper |
| `coolercontrol/` | CoolerControl status/click + API helper + UI-pass sync + dumps ([deps](../README.md#dependencies)) |
| `openlinkhub/` | OpenLinkHub status (hides when service/API down; PSU prefers corsairpsu — [deps](../README.md#dependencies)) |
| `hypr/` | hypr-bar modules, hyprwhspr wrapper |
| `desktop/` | nightlight |

## Path convention

- `WAYBAR_SCRIPTS` is always `$WAYBAR_HOME/scripts` (the tree root).
- Generators emit `$WAYBAR_HOME/scripts/<domain>/<file>`.
- Cross-folder `source`/`exec` use `$WAYBAR_SCRIPTS/<domain>/…`.
- Same-folder siblings may use `${0%/*}/sibling.sh`.

```bash
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
```

## Growth rules

1. Put a new feature’s status/click/popup scripts in the matching domain folder.
2. Shared code goes in `lib/`.
3. Long-running watchers go in `listeners/`.
4. Codegen goes in `generate/`; tests/hooks in `ci/`; ops in `infra/`.
5. If a domain grows past ~20 files, split it further (as with `services/<concern>/`).

## Local checks

From the repo root:

```bash
make check           # full gate (suites + drift + lint)
make check-fast      # syntax + contracts + inventory + validate + systemd + python
make check-syntax    # bash -n
make check-python    # py_compile
make check-ruff      # ruff
make check-systemd   # unit path smoke
make check-generator # scripts/ci/tests/generator/*.sh (CI matrix shards these)
make check-secrets   # scripts/ci/tests/secrets/*.sh
make check-suite-inventory
make check-drift     # regenerate + git diff
make fmt-shell       # shfmt -w
make install-hooks   # secrets pre-commit symlink
```

### CI test layout

| Path | Role |
|------|------|
| `ci/lib/waybar-test-harness.sh` | Entrypoint — sources the focused modules below |
| `ci/lib/waybar-test-core.sh` | `begin` / `end` / `fail` / root / chmod |
| `ci/lib/waybar-test-sandbox.sh` | Tree populate, generator + secrets sandboxes |
| `ci/lib/waybar-test-assert.sh` | JSONC read, secrets write, jq/mode asserts |
| `ci/lib/waybar-test-stubs.sh` | PATH/script stubs + tracked `mktemp` |
| `ci/lib/waybar-test-validate.sh` | Generated-config validators (drawer/module contracts) |
| `ci/lib/fixtures/` | Shared fixtures (settings JSONC, bin/script stubs) |
| `ci/waybar-test-sanitize-env.sh` | Clears fixture/override env bleed between suites |
| `ci/tests/generator/*.sh` | Generator suites (CI matrix shards each file) |
| `ci/tests/secrets/*.sh` | Secrets/settings suites (CI matrix shards each file) |
| `ci/check-suite-inventory.sh` | Fails if CI matrix names ≠ on-disk suite stems |
| `ci/check-generated-drift.sh` | `make generate` then `git diff` on committed artifacts |
| `ci/install-hooks.sh` | Symlink secrets pre-commit (`make install-hooks`) |

Generator shards: `generate-smoke`, `drawer-sot-contracts`, `listener-lifecycle`, `settings-overrides-modules`, `settings-overrides-polish`, `settings-overrides-layout-theme`, `lib-utils`, `generator-resilience`, `path-edge-cases`, `liquidctl`, `coolercontrol-module-wiring`, `coolercontrol-module-auth`, `asusctl`, `hw-nvme-olh`, `hw-rgb-fans`, `portability`.

Secrets shards: `overlay-getters`, `capture-lib`, `credential-guards`, `i2pd-sync`, `coolercontrol-sync-bootstrap`, `coolercontrol-sync-auth`, `polish-runtime`, `compositor-gate`, `precommit-secrets`.

CI `secrets:` path filter in `.github/workflows/ci.yml` must stay aligned with `waybar_test_secrets_sandbox` / `waybar_test_secrets_copy_polish_scripts` / `waybar_test_install_script_stubs` (fixture `app-open.sh` stub — not real `scripts/tools/**`).

Suites source the harness entrypoint only. Run one suite directly:

```bash
bash scripts/ci/tests/generator/liquidctl.sh
bash scripts/ci/tests/secrets/i2pd-sync.sh
```
