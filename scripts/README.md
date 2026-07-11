# Scripts layout

Scripts are grouped so related status/click/popup pairs stay together, with shared infrastructure in top-level folders.

| Folder | Purpose |
|--------|---------|
| `lib/` | Shared helpers (`waybar-settings`, cache helpers, `*-lib`, compositor helpers, signals) |
| `generate/` | Config generators (`generate-*.sh`) |
| `ci/` | Contract checks, unit tests, validate, pre-commit hook |
| `infra/` | Launch, healthcheck, listener-ctl, metrics collector |
| `listeners/` | Long-running watchers |
| `side-info/` | Side drawer tabs/summaries |
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
make check          # syntax + contracts + generator (incl. secrets) + validate + systemd + python
make check-syntax   # bash -n
make check-python   # py_compile
make check-systemd  # unit path smoke
```
