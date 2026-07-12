# Scripts layout

Scripts are grouped so related status/click/popup pairs stay together, with shared infrastructure in top-level folders.

| Folder | Purpose |
|--------|---------|
| `lib/` | Shared helpers — see table below |
| `generate/` | Config generators (`generate-*.sh`); `generate-settings.sh` orchestrates network/dock/domain emitters |
| `ci/` | Contract checks, unit tests, validate, pre-commit hook |
| `infra/` | Launch, healthcheck, listener-ctl, metrics collector |
| `listeners/` | Long-running watchers (`active-window-listener-kde.py` + `lib/kde_listener/` mixins) |
| `dock/` | Dock launcher + dock-windows |
| `workspaces/` | Workspaces, active window, keybind hints |
| `system/` | CPU/mem/disk/gpu/nvme/fans/liquidctl/asusctl/rgb/power/brightness/… |
| `network/` | Wi‑Fi, VPN, ethernet, Tailscale, … |
| `media/` | Audio, mic, MPRIS; optional `cava-status.sh` visualizer ([`cava`](https://github.com/karlstav/cava) — see [Dependencies](../README.md#optional-telemetry--integrations)) |
| `notifications/` | Notifications + clipboard |
| `capture/` | Screenshot / screenrecord / color picker |
| `services/` | Third-party integrations (see subfolders below) |
| `tools/` | Small UX helpers (`app-open`, `calendar-popup`, `pomodoro-*`) |

### `lib/` helpers

| File / package | Role |
|----------------|------|
| `waybar-cache-helpers.sh` | Intervals, cache/locks, `serve_*`, `emit_waybar_json` |
| `waybar-locale-lib.sh` | `detect_*` clock/date/weather + `format_locale_*` (`WAYBAR_WEATHER_UNIT` pins unit for CI) |
| `locale_temp.py` | Python twin of `format_locale_temp` (CoolerControl etc.) |
| `waybar-systemd-scan-lib.sh` | `check_systemd_scan_service` (libredefender / chkrootkit) |
| `waybar-settings.sh` | Settings compile / getters |
| `rofi-popup-lib.sh` | Shared Rofi header/hints rows + `center_text` |
| `network-ip-lib.sh` | `get_public_ip` (multi-endpoint curl/wget) |
| `xdg-applications.sh` / `xdg-icons-lib.sh` | Desktop dirs + icon map / `guess_icon` |
| `gtk_popup_helpers.py` | Shared mouse position / public IP for GTK popups |
| `system-metrics-{cpu,gpu,top}.sh` | Sourced by `infra/system-metrics-collector.sh` |
| `kde_listener/` | Mixins/helpers for the KDE session listener |

### `generate/` domain emitters

`generate-settings.sh` runs network + dock generators, then these domain scripts (no pass-through orchestrator):

`generate-utilities-modules.sh`, `generate-audio-modules.sh`, `generate-clock-modules.sh`, `generate-drawers-modules.sh`, `generate-network-custom-modules.sh`, `generate-privacy-modules.sh`, `generate-active-window-modules.sh`, `generate-center-extras-modules.sh`, `generate-dock-windows-modules.sh`, `generate-tray-modules.sh`, `generate-hypr-tools-modules.sh`, `generate-theme-tokens.sh`.

Sibling scripts (also invoked from Makefile / launch): `generate-compositor-modules.sh`, `generate-workspaces-css.sh`, `generate-dock-modules.sh`, `generate-network-modules.sh`.

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
| `homelab/` | HTTP health probes from `homelab.targets` |
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
