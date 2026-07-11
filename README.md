# Waybar Configuration

A modern, highly modular, and performance-optimized Waybar configuration tailored for KDE Plasma 6 and Hyprland compositors under Wayland.

License: [MIT](LICENSE).

## Features

- **Independent Active Workspace Indicators per Monitor**: Tracks and maps virtual desktops per output using a custom KWin DBus listener script, solving the global workspace tracking limitation in KDE Plasma.
- **Unified Compositor Detection**: Automatically detects whether you are running KDE Plasma or Hyprland, loading the appropriate workspace and window watchers seamlessly.
- **Declarative Code Generation**: Generates Waybar layouts, modules, and theme tokens dynamically from a single central JSONC file (`data/waybar-settings.jsonc`).
- **Smart Caching & Background Refresh**: Employs a zero-lag background-refresh caching mechanism via `scripts/lib/waybar-cache-helpers.sh` (using `serve_cache_or_refresh`). Serves cached UI state instantly on poll, then asynchronously runs updates in the background, preventing CPU stampedes and sluggish updates.
- **Rich Cyberpunk Aesthetics**: High-refresh-rate-friendly pill containers, responsive icons, subtle hover micro-animations, and dynamic sliders.

## File Structure

* `config.jsonc`: Main bar entry point mapping includes and layouts.
* `data/`: Settings SoT (`waybar-settings.jsonc` → compiled `waybar-settings.json`), optional secrets (`waybar-secrets.jsonc`, gitignored), dock/network/workspace manifests.
* `layouts/`: Top and bottom bar layouts (hand-written shells + `.generated.jsonc`).
* `modules/`: Widget configs — almost all are `.generated.jsonc` from settings; do not edit those by hand.
* `includes/`: Include stack wiring modules into the bar.
* `scripts/`: Status/click handlers, listeners, generators, and CI — domain folders plus `lib/`, `generate/`, `ci/`, `infra/`. See [scripts/README.md](scripts/README.md).
* `systemd/`: Portable user units (`waybar.service`, healthcheck service + timer) using `%h/.config/waybar`.
* `theme/`: CSS tokens/modules plus Rofi themes under `theme/rofi/`.
* `style.css` / `user-style.css` / `theme.css`: Bar stylesheet entry points (`style.css` also imports hyprwhspr styles when installed).

## Getting Started

### Installation

See [Dependencies](#dependencies) for core packages and optional telemetry (Arch/CachyOS, Debian/Ubuntu, Fedora). Modules hide when their tools are absent.

1. Clone this repository directly to your Waybar home directory:
   ```bash
   git clone https://github.com/bolens/waybar-config.git ~/.config/waybar
   cd ~/.config/waybar
   ```

2. Post-clone checklist:
   ```bash
   # Optional secrets overlay (i2pd console, etc.)
   cp -n data/waybar-secrets.example.jsonc data/waybar-secrets.jsonc
   chmod 600 data/waybar-secrets.jsonc   # required: secrets must not be world-readable

   # Regenerate modules/layouts from settings
   make generate

   # Install systemd user units (portable %h paths)
   mkdir -p ~/.config/systemd/user
   ln -sfn ~/.config/waybar/systemd/waybar.service ~/.config/systemd/user/waybar.service
   ln -sfn ~/.config/waybar/systemd/waybar-healthcheck.service ~/.config/systemd/user/waybar-healthcheck.service
   ln -sfn ~/.config/waybar/systemd/waybar-healthcheck.timer ~/.config/systemd/user/waybar-healthcheck.timer

   # Block accidental secret commits
   make install-hooks
   ```

3. Enable the systemd user units (recommended):
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now waybar
   systemctl --user enable --now waybar-healthcheck.timer
   ```

   Or start via the launcher (builds settings, configures session paths, listens to session state):
   ```bash
   ~/.config/waybar/scripts/infra/waybar-launch.sh
   ```

### Ops notes (systemd)

| Unit | Role |
|------|------|
| `waybar.service` | Runs `scripts/infra/waybar-launch.sh`; `ExecStop`/`ExecStartPre` call `scripts/infra/listener-ctl.sh stop-all`; reload uses `kill -USR2 $MAINPID` |
| `waybar-healthcheck.timer` | Every ~10s: restart dead waybar, heal privacy / device-notifier / compositor listeners |

Templates live in [`systemd/`](systemd/) and use `%h/.config/waybar`. Do **not** start a second waybar alongside the user service (duplicates bars and listeners).

Keep `WAYBAR_HOME` / `WAYBAR_SCRIPTS` set (scripts root is still `$WAYBAR_HOME/scripts`). Generated module `exec` paths use `$WAYBAR_HOME/scripts/…` so the bar stays portable across users/machines.

Avoid drop-ins that override `ExecStart=` with an absolute `/home/…` path (that caused post-reorg `No such file` storms when templates used `%h` but the drop-in pinned an old layout). Prefer the repo unit as-is; see `systemd/waybar.service.d/README.conf.example`.

### Layer / tooltips (Plasma)

`bars.layer` is **`overlay`** so KWin renders tooltips. Using `"top"` can fix fullscreen overlap but breaks tooltips on Plasma Wayland. Keep `bars.tooltip: true`.

### Hyprland / hyprwhspr

On Hyprland, `custom/hyprwhspr` comes from generated `modules/hypr-tools.generated.jsonc` (via `scripts/services/hypr/hyprwhspr-status-wrapper.sh`). Clicks call the system hyprwhspr tray scripts under `/usr/lib/hyprwhspr/…`. `style.css` imports hyprwhspr’s CSS when the package is installed. No separate hand-written hyprwhspr module file is required.

## Development & Customization

### Central Configuration
Avoid editing `.generated.jsonc` or `.generated.css` files directly. Customize thresholds, poll intervals, application bindings, signals, and colors in:
👉 **[data/waybar-settings.jsonc](data/waybar-settings.jsonc)**

`data/waybar-settings.json` is a compiled artifact and will be overwritten.

Interval / cache TTLs live in a single map: `module_intervals` (there is no separate `poll_intervals`). Status scripts read TTLs via `waybar_module_interval`.

**Personalization:** click targets, app IDs, and URLs under `apps` / service blocks (e.g. Portainer, Syncthing GUI) are machine-specific. Forks should edit those in `data/waybar-settings.jsonc` (or overlay locally) rather than expecting upstream defaults to match your hosts.

### Secrets (i2pd console / CoolerControl)

Credentials that must not be committed live in **`data/waybar-secrets.jsonc`** (gitignored). It is merged over `waybar-settings.jsonc` at read time by `waybar_settings_get`.

| File | Role |
|------|------|
| `data/waybar-secrets.jsonc` | Local secrets (mode `0600`, never commit) |
| `data/waybar-secrets.example.jsonc` | Safe template to copy |
| `scripts/services/i2pd/i2pd-set-console-pass.sh` | i2pd sync helper (run with `sudo`) |
| `scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh` | CoolerControl bootstrap helper (run with `sudo`) |

**`scripts/services/i2pd/i2pd-set-console-pass.sh`** (idempotent):

1. If secrets already have `services.i2pd.console_pass` → push it into `/etc/i2pd/i2pd.conf` `[http]` (and ensure `/var/lib/i2pd/i2pd.conf` is the tmpfiles symlink to `/etc`).
2. If secrets are missing/`CHANGE_ME` but i2pd.conf already has `[http] pass` → **import** that pass into `waybar-secrets.jsonc` (create/update, `chown` to the sudo caller), then continue.
3. Re-run with matching state → no config rewrite, no service restart; auth check only.
4. Password never appears on process argv or in script output.

```bash
sudo ~/.config/waybar/scripts/services/i2pd/i2pd-set-console-pass.sh
```

**`scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh`** (idempotent):

CoolerControl stores a password *hash* (not plaintext), so this helper cannot import/push like i2pd. Instead it:

1. `systemctl enable --now coolercontrold` so the daemon stays running across reboots.
2. If secrets already have `services.coolercontrol.ui_pass` and/or `token` → verify API auth (Bearer `/status` first; `ui_pass` via `POST /login` only if the token is missing or rejected).
3. If secrets are missing → interactive prompt (or `CC_UI_PASS_ENV` / `CC_TOKEN_ENV`) → write `waybar-secrets.jsonc` → verify.
4. Prefer a **read-only Access Token** (`cc_…` from CoolerControl → Access Protection) over the admin UI password for Waybar. Status/click scripts always try `token` first and fall back to `ui_pass` if Bearer auth fails.

```bash
sudo ~/.config/waybar/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh
```

After credentials are in secrets, dump live `/devices` + `/status` shapes (for debugging the module):

```bash
~/.config/waybar/scripts/services/coolercontrol/coolercontrol-api-dump.sh --write
~/.config/waybar/scripts/services/coolercontrol/coolercontrol-check-auth.sh
```

**Write vs read-only tokens:** the status module probes `PATCH /settings {}` (200 = write, 403 = read-only) and sets CSS class `writable` / `readonly`. With a **write** token and CoolerControl Modes configured:

- Scroll up/down → cycle modes (`coolercontrol-click.sh next|prev`)
- Right-click → rofi mode picker (`menu`); falls back to notify if read-only or no modes

Read-only tokens keep monitoring only (left-click opens UI, middle refreshes). Prefer read-only for day-to-day monitoring.

OpenAPI reference: https://coolercontrol.org/openapi/ (`POST /login`, `GET /status` → `StatusResponse.devices[].status_history[]`).

To regenerate configurations after modifying settings:
```bash
make generate
# equivalent:
#   scripts/generate/generate-settings.sh          # also runs network/dock/domain module generators
#   scripts/generate/generate-compositor-modules.sh
#   scripts/generate/generate-workspaces-css.sh
```

Launch skips regeneration when inputs are unchanged (stamp: `~/.cache/waybar/generated.stamp`).

### Adding new status modules
If you are developing a new status script (e.g. `scripts/system/my-status.sh`):
1. Place it in the matching domain folder (see [scripts/README.md](scripts/README.md)).
2. Import the cache helpers at the top of your script (add `waybar-locale-lib.sh` if you call `detect_*` / `format_locale_*`):
   ```bash
   : "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
   : "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
   . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
   ```
3. Leverage the unified caching function to eliminate boilerplate:
   ```bash
   ttl="$(waybar_module_interval my_module 60)"
   if [ "${1:-}" != "--refresh" ]; then
     if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
       exit 0
     fi
     emit_waybar_json "󰄜 --" "Initializing..." "normal"
     exit 0
   fi
   # ... implement your --refresh data fetching logic here ...
   ```
4. Point the generator (or module config) at `$WAYBAR_HOME/scripts/<domain>/my-status.sh`.

### Testing & Validation

```bash
make check           # full gate: suites + drift + lint (shfmt/ruff/gitleaks/stylelint/markdownlint)
make check-fast      # syntax + contracts + inventory + validate + systemd + python
make check-syntax    # bash -n over all scripts
make check-python    # py_compile
make check-ruff      # ruff check scripts/
make check-systemd   # systemd unit templates → real scripts
make check-generator # scripts/ci/tests/generator/*.sh (CI runs these as a matrix)
make check-secrets   # scripts/ci/tests/secrets/*.sh (CI runs these as a matrix)
make check-suite-inventory  # CI matrix ↔ on-disk suite files
make check-drift     # make generate then fail on dirty generated artifacts
make fmt-shell       # shfmt -w scripts/
make install-hooks   # symlink secrets pre-commit hook
```

Or run a single suite / validator:

```bash
~/.config/waybar/scripts/ci/validate-generated-config.sh
~/.config/waybar/scripts/ci/tests/generator/liquidctl.sh
~/.config/waybar/scripts/ci/tests/secrets/i2pd-sync.sh
```

Shared helpers live under `scripts/ci/lib/` (`waybar-test-harness.sh` entrypoint + focused `core` / `sandbox` / `assert` / `stubs` / `validate` modules + `fixtures/`). Suite inventory and CI path filters are documented in [scripts/README.md](scripts/README.md#ci-test-layout).

CI workflows (as of 2026-07): main `CI` (path-filtered suites + generated drift + suite inventory + `CI result` aggregator; `workflow_dispatch` / weekly full run), plus ShellCheck, actionlint, shfmt, Ruff, Gitleaks, Stylelint, and Markdownlint. Pin notes: `actions/checkout@v7`, `actions/setup-node@v6`, `pnpm/action-setup@v6.0.9`, Corepack + `pnpm@11.11.0`, `dorny/paths-filter@v4`, `astral-sh/ruff-action@v4.1.0`, ShellCheck action `2.0.0`, actionlint `1.7.12`, shfmt `3.13.1`, gitleaks `8.30.1`.

ShellCheck runs at **warning** severity (see `.shellcheckrc`).

## Dependencies

Modules that wrap optional tools **hide** (Waybar `disconnected`) when the binary/daemon is missing or inactive. Install only what you use.

Package names below target the distros Waybar is commonly packaged for: **Arch / CachyOS / Manjaro**, **Debian / Ubuntu**, and **Fedora**. Prefer your distro’s packages when names differ slightly.

### Core (recommended)

| Need | Arch / CachyOS | Debian / Ubuntu | Fedora |
|------|----------------|-----------------|--------|
| JSON helpers | `jq` | `jq` | `jq` |
| Hyprland IPC | `socat` | `socat` | `socat` |
| KDE DBus helpers | `qt6-tools` | `qt6-tools` | `qt6-qttools` |
| Audio (PipeWire session) | `wireplumber` | `wireplumber` | `wireplumber` |
| Menus | `rofi` and/or `wofi` | `rofi` / `wofi` | `rofi` / `wofi` |
| Clipboard history | `cliphist` | `cliphist` | `cliphist` |

```bash
# Arch / CachyOS
sudo pacman -S jq socat qt6-tools wireplumber rofi cliphist

# Debian / Ubuntu
sudo apt install jq socat qt6-tools wireplumber rofi cliphist

# Fedora
sudo dnf install jq socat qt6-qttools wireplumber rofi cliphist
```

### Optional telemetry & integrations

| Module / feature | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|------------------|----------------|-----------------|--------|-------|
| NetworkManager status | `networkmanager` | `network-manager` | `NetworkManager` | |
| Brightness | `brightnessctl` | `brightnessctl` | `brightnessctl` | |
| External monitor DDC | `ddcutil` | `ddcutil` | `ddcutil` | |
| Docker / containers | `docker` | `docker.io` | `docker` | |
| Device / battery (UPower) | `upower` | `upower` | `upower` | |
| Logitech battery fallback | `solaar` | `solaar` | `solaar` | Used only if sysfs Device batteries are missing |
| UPS (`custom` NUT path) | `nut` | `nut-client` / `nut` | `nut` | |
| AIO / USB coolers (`custom/liquidctl`) | `liquidctl` | `liquidctl` | `liquidctl` | **AIO/hubs only** when Corsair PSU is covered by hwmon; Aura RGB skipped in favor of OpenRGB/ckb-next |
| Digital Corsair PSU (`custom/psu`) | kernel `corsair-psu` / `corsairpsu` hwmon | same (in-tree hwmon) | same | No userspace package — load module if needed: `sudo modprobe corsair-psu` |
| CoolerControl (`custom/coolercontrol`) | AUR `coolercontrol-bin` or `coolercontrol` | Cloudsmith → `coolercontrol` ([docs](https://docs.coolercontrol.org/installation/debian.html)) | Copr `codifryed/CoolerControl` → `coolercontrol` ([docs](https://docs.coolercontrol.org/installation/fedora.html)) | Enable `coolercontrold`; sync secrets with `coolercontrol-set-ui-pass.sh`. Write-access probe is cached (~10m). |
| OpenLinkHub (`custom/openlinkhub`) | AUR `openlinkhub-bin` / `openlinkhub` | `.deb` from [releases](https://github.com/jurkovic-nikola/OpenLinkHub/releases) or [PPA](https://github.com/jurkovic-nikola/OpenLinkHub#installation-ppa) | `.rpm` from releases | Presence/UI for linked Corsair devices; **PSU sensors prefer `custom/psu`**. Enable `openlinkhub.service`. HID ownership can conflict with liquidctl — prefer one owner per device. |
| ASUS / ROG profiles (`custom/asusctl`) | `asusctl` (g14 repo or AUR) | build from [asus-linux](https://asus-linux.org/guides/asusctl-install/) (not officially packaged) | [asus-linux Fedora packages](https://asus-linux.org/) | Hides when `asusd` is unavailable |
| RGB daemon presence (`custom/rgb`) | `openrgb` and/or `ckb-next` | `openrgb` / `ckb-next` | `openrgb` / `ckb-next` | Module shows only while a daemon is running |
| NVIDIA GPU metrics | `nvidia-utils` (provides `nvidia-smi`) | NVIDIA driver packages | NVIDIA driver packages | Falls back to `amdgpu` hwmon if NVIDIA is suspended/missing |
| Fan curves note (`custom/fans` tooltip) | `fanctl` (community/AUR) | install from upstream if packaged | same | Optional note only — does not replace hwmon fans |
| Hyprland voice (`hyprwhspr`) | project install | project install | project install | Optional CSS import in `style.css` |
| Sensors / lm-sensors | `lm_sensors` | `lm-sensors` | `lm_sensors` | Helps hwmon labels; not required for every module |
| LibreDefender (`custom/libredefender`) | `libredefender` (+ `clamav` / `clamav-freshclam`) | build from [upstream](https://github.com/kpcyrd/libredefender) or ClamAV packages | same | Wire `services.libredefender.service_name` to your scan unit (default `libredefender-scan.service`) |
| chkrootkit (`custom/chkrootkit`) | AUR `chkrootkit` | `chkrootkit` | `chkrootkit` | Wire `services.chkrootkit.service_name` to your scan unit (default `chkrootkit-scan.service`) |
| System updates (`custom/updates`) | `pacman-contrib` (`checkupdates`); optional `paru` for AUR | `apt` (base) | `dnf` (base) | Auto-detects backend; Flatpak optional additive |

**Kernel / sysfs (no package)** — used when present:

| hwmon / path | Module |
|--------------|--------|
| `corsairpsu` (`corsair-psu`) | `custom/psu` (rails, watts, fan, temps) |
| NVMe `hwmon` | `custom/nvme` |
| `asusec` | `custom/fans` (CPU cooler RPM) |
| `nct6799` | `custom/fans` (chassis max RPM supplement) |
| `amdgpu` | GPU fallback when `nvidia-smi` unavailable |

### Telemetry source priority (avoid duplicate probes)

Richer / cheaper sources win; modules skip or hide when covered:

1. **Corsair digital PSU** → `corsairpsu` hwmon (`custom/psu`) over liquidctl HID and over OpenLinkHub PSU temps  
2. **liquidctl** → exclusive AIO/hub telemetry only; hides when only PSU/Aura remain  
3. **OpenLinkHub** → device presence + UI; points at PSU module when the only device is a Corsair PSU already in hwmon  
4. **Aura / RGB** → OpenRGB or ckb-next (`custom/rgb`), not liquidctl  
5. **Fans** → asusec + GPU metrics + nct6799; PSU fan deferred to `custom/psu` when corsairpsu exists  
6. **CoolerControl** → mode control / daemon UI — does not replace nvme/fans/gpu modules  

### Example: Arch / CachyOS (this repo author’s stack)

```bash
# Core + common telemetry
sudo pacman -S jq socat qt6-tools wireplumber rofi cliphist \
  networkmanager brightnessctl ddcutil upower solaar nut liquidctl \
  openrgb ckb-next lm_sensors

# Optional AUR / community (yay/paru) — pick what you own
yay -S coolercontrol-bin openlinkhub-bin   # or coolercontrol / openlinkhub
# asusctl: prefer asus-linux g14 repo, or AUR asusctl
sudo systemctl enable --now coolercontrold
sudo systemctl enable --now openlinkhub

# Corsair PSU sysfs (if not already loaded)
sudo modprobe corsair-psu
# Optional: persist via /etc/modules-load.d/corsair-psu.conf → corsair-psu

# CoolerControl Waybar secrets (after daemon is up)
sudo ~/.config/waybar/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh
```

### Example: Debian / Ubuntu

```bash
sudo apt install jq socat qt6-tools wireplumber rofi cliphist \
  network-manager brightnessctl ddcutil upower solaar nut-client liquidctl \
  openrgb lm-sensors

# CoolerControl — https://docs.coolercontrol.org/installation/debian.html
curl -1sLf 'https://dl.cloudsmith.io/public/coolercontrol/coolercontrol/setup.deb.sh' | sudo -E bash
sudo apt update && sudo apt install coolercontrol
sudo systemctl enable --now coolercontrold

# OpenLinkHub — .deb from GitHub releases or PPA (see upstream README)
sudo systemctl enable --now openlinkhub
```

### Example: Fedora

```bash
sudo dnf install jq socat qt6-qttools wireplumber rofi cliphist \
  NetworkManager brightnessctl ddcutil upower solaar nut liquidctl \
  openrgb lm_sensors

# CoolerControl — https://docs.coolercontrol.org/installation/fedora.html
sudo dnf install dnf-plugins-core
sudo dnf copr enable codifryed/CoolerControl
sudo dnf install coolercontrol
sudo systemctl enable --now coolercontrold

# OpenLinkHub — .rpm from GitHub releases
sudo systemctl enable --now openlinkhub
```

### Portability & environment overrides

Scripts resolve config via `WAYBAR_HOME` → `$XDG_CONFIG_HOME/waybar` → `~/.config/waybar`. Sysfs and capture paths are overridable for tests and non-standard layouts:

| Variable | Purpose |
|----------|---------|
| `WAYBAR_HOME` / `WAYBAR_SCRIPTS` | Config and scripts roots |
| `WAYBAR_COMPOSITOR` | Force `hyprland` / `kde` / `unknown` |
| `WAYBAR_HWMON_ROOT` | Fake or alternate `/sys/class/hwmon` (psu, fans, liquidctl, metrics, OLH) |
| `WAYBAR_THERMAL_ROOT` | Alternate `/sys/class/thermal` (metrics collector) |
| `WAYBAR_POWER_SUPPLY_ROOT` | Alternate `/sys/class/power_supply` (device battery) |
| `WAYBAR_NVME_HWMON_ROOT` | NVMe hwmon scan root |
| `WAYBAR_OLH_API_URL` | OpenLinkHub API base URL |
| `WAYBAR_SCREENSHOT_DIR` / `WAYBAR_SCREENRECORD_DIR` | Override capture dirs (wins over settings) |
| `WAYBAR_UPDATES_BACKEND` | Force `arch` / `apt` / `dnf` / `none` |
| `WAYBAR_UPDATES_ENABLE_AUR` | `1`/`0` overrides `updates.enable_aur` (Arch only) |

**Updates backends** (`custom/updates`): prefer `checkupdates` (Arch) → `apt` → `dnf`; Flatpak is additive. AUR/`paru` only on the Arch path when `enable_aur` is set — never hard-required. Review click uses `apps.paru_update` / `apt_update` / `dnf_update` when set, else a terminal with the matching upgrade command.

**Capture dirs**: defaults are `${XDG_PICTURES_DIR:-~/Pictures}/Screenshots` and `${XDG_VIDEOS_DIR:-~/Videos}/Screenrecordings` (settings `capture.*_dir` null, or set explicitly e.g. `/mnt/media/…` on a media host). Env overrides above win over settings.

**Desktop apps**: window switcher and KDE notification icons walk `$XDG_DATA_HOME/applications`, each `$XDG_DATA_DIRS/…/applications`, then Flatpak export dirs.