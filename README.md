# Waybar Configuration

A modern, highly modular, and performance-optimized Waybar configuration tailored for KDE Plasma 6 and Hyprland compositors under Wayland.

License: [MIT](LICENSE).

## Documentation

Full map (keep in sync when adding pages): **[docs/README.md](docs/README.md)**

| Doc | Topic |
|-----|--------|
| [docs/README.md](docs/README.md) | Documentation index (canonical) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Setup, checks, secrets, PR norms |
| [AGENTS.md](AGENTS.md) | Short briefing for AI coding agents |
| [docs/architecture.md](docs/architecture.md) | Settings → generate → Waybar pipeline |
| [docs/settings-reference.md](docs/settings-reference.md) | Top-level keys in `waybar-settings.jsonc` |
| [docs/adding-a-module.md](docs/adding-a-module.md) | Checklist for new status modules |
| [docs/theming.md](docs/theming.md) | Presets, wallpaper, floating, reduced motion |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failures and fixes |
| [docs/mcp.md](docs/mcp.md) | Optional MCP server for AI assistants |
| [scripts/README.md](scripts/README.md) | Script layout, growth rules, CI harness |

## Features

- **Independent Active Workspace Indicators per Monitor**: Tracks and maps virtual desktops per output using a custom KWin DBus listener script, solving the global workspace tracking limitation in KDE Plasma.
- **Unified Compositor Detection**: Automatically detects whether you are running KDE Plasma or Hyprland, loading the appropriate workspace and window watchers seamlessly.
- **Declarative Code Generation**: Generates Waybar layouts, modules, and theme tokens dynamically from a single central JSONC file (`data/waybar-settings.jsonc`).
- **Smart Caching & Background Refresh**: Employs a zero-lag background-refresh caching mechanism via `scripts/lib/waybar-cache-helpers.sh` (using `serve_cache_or_refresh`). Serves cached UI state instantly on poll, then asynchronously runs updates in the background, preventing CPU stampedes and sluggish updates.
- **Rich Cyberpunk Aesthetics**: High-refresh-rate-friendly pill containers, responsive icons, subtle hover micro-animations, and dynamic sliders.
- **Optional audio visualizer**: `custom/cava` in the media drawer (requires [`cava`](https://github.com/karlstav/cava); hides when missing or silent).
- **MCP server for AI agents**: stdlib Python MCP (`scripts/mcp/waybar-mcp.py`) exposes settings, themes, generate/validate, and more — see [docs/mcp.md](docs/mcp.md).

## File Structure

* `config.jsonc`: Main bar entry point mapping includes and layouts.
* `data/`: Settings SoT (`waybar-settings.jsonc` → compiled `waybar-settings.json`), optional secrets (`waybar-secrets.jsonc`, gitignored), dock/network/workspace manifests.
* `layouts/`: Top and bottom bar layouts (hand-written shells + `.generated.jsonc`).
* `modules/`: Widget configs — almost all are `.generated.jsonc` from settings; do not edit those by hand.
* `includes/`: Include stack wiring modules into the bar.
* `scripts/`: Status/click handlers, listeners, generators, and CI — domain folders plus `lib/`, `generate/`, `ci/`, `infra/`. See [scripts/README.md](scripts/README.md).
* `systemd/`: Portable user units (`waybar.service`, healthcheck service + timer) using `%h/.config/waybar`.
* `theme/`: CSS tokens/modules plus Rofi themes under `theme/rofi/`.
* `style.css` / `theme.css`: Import hubs. Shared accents live under `theme/accents/`; personal overrides under `user-style/` (imported last from `style.css`). (`style.css` also imports hyprwhspr styles when installed.)

## Getting Started

### Installation

See [Dependencies](#dependencies) for core packages and optional tools (media, network, capture, devices, hardware telemetry, security, wallpaper backends). Modules hide when their tools are absent.

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

See the full checklist: **[docs/adding-a-module.md](docs/adding-a-module.md)**.

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

### MCP server (AI assistants)

Optional [Model Context Protocol](https://modelcontextprotocol.io/) server so coding agents can inspect and edit this config safely (stdlib only, no pip deps):

```bash
python3 scripts/mcp/waybar-mcp.py --register   # Cursor / Claude Desktop / Windsurf
# or add manually — see docs/mcp.md
```

Typical agent flow: `waybar_backup_settings` → patch/theme/group tools → `waybar_generate` → `waybar_validate` → `waybar_restart` (`confirm=true`). Live secrets are never written via MCP. Full tool/resource/prompt tables: [docs/mcp.md](docs/mcp.md).

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
make check-suite-inventory  # CI matrix ↔ on-disk suite files (+ CSS path filters)
make check-docs-index       # docs/README.md ↔ docs/*.md + hub backlinks
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

## Module catalog

Groups and module lists live in `data/waybar-settings.jsonc` → `groups.*` (see also [`scripts/README.md`](scripts/README.md)). Common modules:

| Module | Group | Binary / dep | Notes |
|--------|-------|--------------|-------|
| `custom/cpu` `gpu` `memory` `disk` `nvme` `psu` | hardware | sysfs / `nvidia-smi` | Threshold CSS: `.warning` / `.critical` (theme tokens) |
| `custom/fans` `liquidctl` `coolercontrol` `openlinkhub` | cooling | optional daemons | Hide when absent; OLH right-click restarts service |
| `custom/cava` | media | **`cava` (optional)** | Continuous bars; hides when silent/missing — see [Dependencies](#optional-media--session) |
| `mpris` / `custom/mpris` / pulse / mic | media | playerctl / PipeWire | Mic left opens `apps.audio_mixer` |
| `custom/album-art` | media | `playerctl` | **On by default**; set `visual.album_art.enabled: false` to hide |
| `custom/pomodoro` | tools | none | Click toggle · right reset · middle skip |
| `custom/weather` | tools | `curl` | Open-Meteo (default) → wttr.in fallback |
| `custom/nightlight` | tools | compositor helpers | Toggle / preview / settings |
| `custom/github` | tools | `gh` | Notifications + review-requested PRs |
| `custom/notifications` | desk-controls | Plasma / mako | Left open · Right DND · Middle settings |
| `custom/clipboard` | tools | cliphist | Left open · Right clear |
| `custom/power-menu` | power | `rofi` | Grid menu; individuals still available |
| `custom/homelab` | infra | `curl` | `homelab.targets[]`; hidden if empty; multi-target → rofi picker |
| `custom/updates` | infra | pacman/apt/dnf | Review → “Upgrade System Now” in terminal |
| `custom/docker` `runtimes` | infra | docker / podman / libvirt | Optional container/VM strip |
| `bluetooth` / `kdeconnect` / `streamdeck` / device battery | devices | optional | Peripherals strip (top bar) |
| `custom/vaults` / security scanners | security | optional | Hide when tools absent |
| `custom/dock-windows` | bottom center | `qdbus6` (Plasma) / `hyprctl` | **On by default**; set `dock_windows.enabled: false` to hide. Plasma: install `qt6-tools`. |
| `custom/stats-carousel` | hardware | metrics collector | **On by default** (`visual.stats_carousel.enabled`); replaces cpu/mem/disk/gpu; scroll to cycle |
| `hyprland/submap` | desk-hypr | Hyprland | Native overlay; shows active submap name |
| Privacy / VPN / Tailscale / i2pd | privacy / net | PipeWire / daemons | |

### Minimal / laptop profile

```bash
make profile-minimal   # merges data/profiles/minimal-groups.jsonc into settings + generate
```

Or manually: merge [`data/profiles/minimal-groups.jsonc`](data/profiles/minimal-groups.jsonc) into `data/waybar-settings.jsonc`, then `make generate`. The apply helper deep-merges and rewrites the jsonc (comments in the base file are not preserved).

### Homelab health

```jsonc
"homelab": {
  "timeout_sec": 3,
  "targets": [
    { "name": "Caddy", "url": "https://example.com/health", "expect": "2xx" },
    { "name": "Uptime Kuma", "url": "http://127.0.0.1:3001", "expect": "2xx" }
  ]
}
```

- **0 targets:** module hidden; left/middle refresh.
- **1 target:** left opens that URL.
- **2+ targets:** left opens a rofi picker; right opens the first URL; middle refreshes.

### Dock windows

**Enabled by default** on the bottom bar center (next to active-window).

#### What you should see

- One **app icon per open window** (up to `dock_windows.slot_count`, default 12), like the workspace switcher.
- The focused window’s glyph is highlighted; others are dimmed.
- Tooltip on each glyph shows that window’s title (full title lives in the active-window module).

#### Clicks

- Left: focus that window.
- Right: close that window.
- Middle: cycle focus.
- No rofi picker here — use the active-window module for that.

#### Known limitation (Plasma)

**Per-monitor** (`dock_windows.per_output`, default on): each bar prefers windows on that output. When WindowsRunner omits screen props, the dock enriches via KWin `getWindowInfo` geometry + `kscreen-doctor` output rects. If those probes fail, both bars may still show the full list. Hyprland per-output filtering uses `hyprctl` client monitor fields.

Set `dock_windows.enabled: false` to hide. Plasma needs `qt6-tools` (`qdbus6`) and `kscreen-doctor` for geometry-based per-output enrich.

### Theming

See **[docs/theming.md](docs/theming.md)** for presets, wallpaper mode, floating glass bars, and reduced motion.

Colors come from `theme` in `data/waybar-settings.jsonc` (then `make generate`):

| `theme.mode` | Behavior |
|--------------|----------|
| `static` | Use `theme.colors.*` (default cyberpunk) |
| `preset` | Load `data/themes/<theme.preset>.jsonc`, then optional `theme.colors` overrides |
| `wallpaper` | Auto matugen → wallust → pywal; default `scope: per_output` styles each monitor. Run `scripts/tools/theme-apply-wallpaper.sh` after wallpaper changes. |

`make generate` writes `theme/tokens.generated.css` (fonts/chrome) and `theme/semantic-colors.generated.css` (warning/critical/dock/workspace colors baked as concrete values — GTK3 has no CSS `var()`). Clock calendar spans and rofi menus pull the same `theme.colors.*`.

**Reduced motion:** `visual.animations.reduced_motion` (`auto` | `force` | `off`). In `auto`, launch probes GNOME `reduced-motion` / `enable-animations`, Plasma `AnimationDurationFactor=0` (Instant), and Hyprland `animations:enabled`. When active, `theme/reduced-motion.generated.css` disables CSS animations/transitions and unicode loading spinners skip. Override with `WAYBAR_REDUCED_MOTION=1|0`.

**Bundled presets:** `cyberpunk`, `glass-cyber`, `minimal`, `nord`, `dracula`, `catppuccin-mocha`, `catppuccin-macchiato`, `gruvbox`, `tokyo-night`, `rose-pine`, `everforest`, `solarized-dark`, `one-dark`.

Example:

```jsonc
"theme": {
  "mode": "preset",
  "preset": "nord"
}
```

Floating glass bars: set `bars.floating: true` (margins + non-exclusive). Optional `bars.glass_opacity` / `bars.chrome_radius`. On Hyprland, add blur with the snippet from `scripts/tools/print-hypr-waybar-blur.sh` (not auto-applied).

### Per-monitor modules

With `bars.output: ["*"]`, bars already appear on every monitor. These honor `$WAYBAR_OUTPUT_NAME` when their `*.per_output` toggle is on (defaults on for most):

- Workspace scroll (`workspaces.scroll_per_output`)
- Active window, brightness, capture full-screen, dock-windows, window switcher
- Wallpaper tokens when `theme.mode=wallpaper` and `theme.wallpaper.scope=per_output`
- Optional Hyprland submap chrome (`hypr_tools.submap_per_output`): scopes `#submap` under each `window.<OUTPUT>` — presentation only; submap state stays session-global

`workspaces.slot_count` is the number of **desktop slots**, not monitors.

### Visual polish

Under `visual` in settings: unicode gauges (`visual.gauges`), album art (signal-driven), stats carousel (**on by default**; scroll cycles cpu/mem/disk/gpu), CSS animations (`workspace_pulse`, `critical_breathe`, `idle_glow`), and `reduced_motion` (`auto` / `force` / `off`). Cava: `cava.placement` `drawer` | `inline`.

## Dependencies

Modules that wrap optional tools **hide** (Waybar `disconnected`) when the binary/daemon is missing or inactive. Install only what you use.

Package names below target the distros Waybar is commonly packaged for: **Arch / CachyOS / Manjaro**, **Debian / Ubuntu**, and **Fedora**. Prefer your distro’s packages when names differ slightly.

### Core (recommended)

| Need | Arch / CachyOS | Debian / Ubuntu | Fedora |
|------|----------------|-----------------|--------|
| JSON helpers | `jq` | `jq` | `jq` |
| HTTP clients (weather, APIs) | `curl` | `curl` | `curl` |
| Fast text search (several scripts) | `ripgrep` (`rg`) | `ripgrep` | `ripgrep` |
| Hyprland IPC | `socat` | `socat` | `socat` |
| KDE DBus helpers | `qt6-tools` (`qdbus6`) | `qt6-tools` | `qt6-qttools` |
| Audio (PipeWire session + `wpctl`) | `wireplumber` | `wireplumber` | `wireplumber` |
| Pulse helpers (`pactl`) | `libpulse` | `pulseaudio-utils` | `pipewire-pulse` / `pulseaudio-utils` |
| Menus | `rofi` and/or `wofi` | `rofi` / `wofi` | `rofi` / `wofi` |
| Clipboard (`wl-copy` / `wl-paste`) | `wl-clipboard` | `wl-clipboard` | `wl-clipboard` |
| Clipboard history | `cliphist` | `cliphist` | `cliphist` |
| Desktop notifications | `libnotify` (`notify-send`) | `libnotify-bin` | `libnotify` |

```bash
# Arch / CachyOS
sudo pacman -S jq curl ripgrep socat qt6-tools wireplumber libpulse \
  rofi wl-clipboard cliphist libnotify

# Debian / Ubuntu
sudo apt install jq curl ripgrep socat qt6-tools wireplumber pulseaudio-utils \
  rofi wl-clipboard cliphist libnotify-bin

# Fedora
sudo dnf install jq curl ripgrep socat qt6-qttools wireplumber pipewire-pulse \
  rofi wl-clipboard cliphist libnotify
```

### Optional media & session

| Module / feature | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|------------------|----------------|-----------------|--------|-------|
| MPRIS / album art (`custom/mpris`, `custom/album-art`) | `playerctl` | `playerctl` | `playerctl` | Album art also needs `curl`; on by default — set `visual.album_art.enabled: false` to hide |
| Scrolling titles (`zscroll`) | AUR `zscroll-git` | build from [upstream](https://github.com/noctuid/zscroll) | same | Optional polish for MPRIS / active-window |
| Audio visualizer (`custom/cava`) | `cava` | `cava` | `cava` | Hides when binary missing or output silent. Config: `cava.bars` / `cava.framerate` |
| Mixer click fallbacks | `pavucontrol` / `pwvucontrol` / AUR `wiremix` | `pavucontrol` | `pavucontrol` | Used when `apps.audio_mixer` is unset |
| Power profiles | `power-profiles-daemon` (`powerprofilesctl`) | `power-profiles-daemon` | `power-profiles-daemon` | |
| Brightness | `brightnessctl` | `brightnessctl` | `brightnessctl` | |
| External monitor DDC | `ddcutil` | `ddcutil` | `ddcutil` | |
| Night light (Hyprland) | `hyprsunset` | `hyprsunset` | `hyprsunset` | Plasma uses Night Color / KWin |
| Lock (power menu) | `hyprlock` and/or `swaylock` | same | same | Compositor-specific |
| Hyprland voice (`hyprwhspr`) | project install | project install | project install | Optional CSS import in `style.css` |
| Keybind hints (`custom/keybindhint`) | AUR `hyprkeys` | build from upstream | same | Falls back to terminal + config path |

### Optional network, VPN & sync

| Module / feature | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|------------------|----------------|-----------------|--------|-------|
| NetworkManager (`nmcli`, interfaces) | `networkmanager` | `network-manager` | `NetworkManager` | Optional GUI: `nm-connection-editor` / `nmtui` |
| Wi‑Fi SSID fallback | `wireless_tools` (`iwgetid`) | `wireless-tools` | `wireless-tools` | |
| Bluetooth (`bluetoothctl`) | `bluez` / `bluez-utils` | `bluez` / `bluez` | `bluez` | Optional GUI: `blueman` |
| Tailscale (`custom/tailscale`) | `tailscale` | `tailscale` | `tailscale` | |
| VPN summary extras | `netbird` / `zerotier-one` / `mullvad-vpn` | upstream packages | same | Detected when present; not required |
| I2P (`custom/i2pd`) | `i2pd` | `i2pd` | `i2pd` | Console password via secrets + `i2pd-set-console-pass.sh` |
| Syncthing (`custom/syncthing`) | `syncthing` | `syncthing` | `syncthing` | |
| Homelab / weather HTTP | `curl` (core) | `curl` | `curl` | `homelab.targets[]`; weather Open-Meteo → wttr.in |

### Optional capture, picker & clipboard polish

| Module / feature | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|------------------|----------------|-----------------|--------|-------|
| Wayland screenshot / region | `grim` + `slurp` | `grim` + `slurp` | `grim` + `slurp` | |
| Hyprland screenshot helper | AUR `grimblast` | rarely packaged | same | Optional; falls back to grim/slurp |
| Screen record (wlroots) | `wf-recorder` | `wf-recorder` | `wf-recorder` | |
| Plasma capture | `spectacle` | `spectacle` | `spectacle` | Preferred on KDE |
| Color picker | `hyprpicker` (Hyprland) / `kcolorchooser` (Plasma) | same | same | X11 fallback: `xclip` |
| Calendar popup | `util-linux` (`cal`) | `bsdmainutils` / `ncal` | `util-linux` | |

### Optional devices, desktop & apps

| Module / feature | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|------------------|----------------|-----------------|--------|-------|
| Device / battery (UPower) | `upower` | `upower` | `upower` | |
| Logitech battery fallback | `solaar` | `solaar` | `solaar` | Used only if sysfs Device batteries are missing |
| KDE Connect | `kdeconnect` (`kdeconnect-cli`) | `kdeconnect` | `kde-connect` | Optional share picker: `zenity` |
| Stream Deck (`custom/streamdeck`) | AUR / chaotic `streamdeck-ui` | pip / upstream `streamdeck-ui` | same | Left-click opens UI; USB probe uses `usbutils` (`lsusb`) |
| Sunshine (`custom/sunshine`) | `sunshine` | Flatpak / upstream | Copr / upstream | |
| GitHub (`custom/github`) | `github-cli` (`gh`) | `gh` | `gh` | |
| Docker (`custom/docker`) | `docker` | `docker.io` | `docker` | |
| Other runtimes (`custom/runtimes`) | `podman` / `libvirt` (`virsh`) / `waydroid` | same | same | Each detected independently |
| Encrypted vaults (`custom/vaults`) | `gocryptfs` (+ `fuse3`) | `gocryptfs` | `gocryptfs` | Uses `findmnt` / `fusermount` from util-linux / fuse |
| Keyboard layout (X11 fallback) | `xorg-setxkbmap` | `x11-xkb-utils` | `setxkbmap` | Plasma prefers `qdbus6` |
| Output discovery extras | `wlr-randr` / `sway` (`swaymsg`) / Plasma `kscreen-doctor` | same | same | Plus `hyprctl` on Hyprland |
| Window focus helpers | `wmctrl` / `xdotool` / `wtype` / `ydotool` | same | same | Optional; Stream Deck / Discord mute paths |

### Optional hardware telemetry

| Module / feature | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|------------------|----------------|-----------------|--------|-------|
| UPS (`custom` NUT path) | `nut` | `nut-client` / `nut` | `nut` | |
| AIO / USB coolers (`custom/liquidctl`) | `liquidctl` | `liquidctl` | `liquidctl` | **AIO/hubs only** when Corsair PSU is covered by hwmon; Aura RGB skipped in favor of OpenRGB/ckb-next |
| Digital Corsair PSU (`custom/psu`) | kernel `corsair-psu` / `corsairpsu` hwmon | same (in-tree hwmon) | same | No userspace package — load module if needed: `sudo modprobe corsair-psu` |
| CoolerControl (`custom/coolercontrol`) | AUR `coolercontrol-bin` or `coolercontrol` | Cloudsmith → `coolercontrol` ([docs](https://docs.coolercontrol.org/installation/debian.html)) | Copr `codifryed/CoolerControl` → `coolercontrol` ([docs](https://docs.coolercontrol.org/installation/fedora.html)) | Enable `coolercontrold`; sync secrets with `coolercontrol-set-ui-pass.sh`. Write-access probe is cached (~10m). |
| OpenLinkHub (`custom/openlinkhub`) | AUR `openlinkhub-bin` / `openlinkhub` | `.deb` from [releases](https://github.com/jurkovic-nikola/OpenLinkHub/releases) or [PPA](https://github.com/jurkovic-nikola/OpenLinkHub#installation-ppa) | `.rpm` from releases | Presence/UI for linked Corsair devices; **PSU sensors prefer `custom/psu`**. Enable `openlinkhub.service`. HID ownership can conflict with liquidctl — prefer one owner per device. |
| ASUS / ROG profiles (`custom/asusctl`) | `asusctl` (g14 repo or AUR) | build from [asus-linux](https://asus-linux.org/guides/asusctl-install/) (not officially packaged) | [asus-linux Fedora packages](https://asus-linux.org/) | Hides when `asusd` is unavailable |
| RGB daemon presence (`custom/rgb`) | `openrgb` and/or `ckb-next` | `openrgb` / `ckb-next` | `openrgb` / `ckb-next` | Module shows only while a daemon is running |
| NVIDIA GPU metrics | `nvidia-utils` (provides `nvidia-smi`) | NVIDIA driver packages | NVIDIA driver packages | Falls back to `amdgpu` hwmon if NVIDIA is suspended/missing |
| Fan curves note (`custom/fans` tooltip) | `fanctl` (community/AUR) | install from upstream if packaged | same | Optional note only — does not replace hwmon fans |
| Sensors / lm-sensors | `lm_sensors` | `lm-sensors` | `lm_sensors` | Helps hwmon labels; not required for every module |

### Optional security & updates

| Module / feature | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|------------------|----------------|-----------------|--------|-------|
| LibreDefender (`custom/libredefender`) | `libredefender` (+ `clamav` / `clamav-freshclam`) | build from [upstream](https://github.com/kpcyrd/libredefender) or ClamAV packages | same | Wire `services.libredefender.service_name` to your scan unit (default `libredefender-scan.service`) |
| chkrootkit (`custom/chkrootkit`) | AUR `chkrootkit` | `chkrootkit` | `chkrootkit` | Wire `services.chkrootkit.service_name` to your scan unit (default `chkrootkit-scan.service`) |
| System updates (`custom/updates`) | `pacman-contrib` (`checkupdates`); optional `paru` for AUR | `apt` (base) | `dnf` (base) | Auto-detects backend; Flatpak optional additive |

### Optional wallpaper theming

Used when `theme.mode=wallpaper` (see [Theming](#theming)). Install at least one backend:

| Backend | Arch / CachyOS | Debian / Ubuntu | Fedora | Notes |
|---------|----------------|-----------------|--------|-------|
| matugen | AUR / crates `matugen` | build / crates | same | Preferred when present |
| wallust | AUR `wallust` | crates / upstream | same | |
| pywal | `python-pywal` / `pywal16` | `python3-pywal` | `python3-pywal` | |
| Wallpaper setter | `swww` | `swww` | `swww` | Optional helper for applying images |

**Click targets** (`apps.*` in settings) are not module gates — point them at whatever you run (`ghostty`, `btop`, `nvtop`, `lazydocker`, `missioncenter`, `kclock`, `virt-manager`, `discord`, GoXLR launcher, etc.).

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
# Core + common desktop / media / network
sudo pacman -S jq curl ripgrep socat qt6-tools wireplumber libpulse \
  rofi wl-clipboard cliphist libnotify \
  playerctl networkmanager bluez bluez-utils brightnessctl ddcutil \
  power-profiles-daemon upower solaar kdeconnect usbutils \
  grim slurp wf-recorder spectacle hyprpicker kcolorchooser \
  nut liquidctl openrgb ckb-next lm_sensors github-cli \
  tailscale syncthing gocryptfs

# Optional: media visualizer, GameStream host, I2P, …
# sudo pacman -S cava sunshine i2pd

# Optional AUR / community (yay/paru) — pick what you own
yay -S coolercontrol-bin openlinkhub-bin streamdeck-ui   # or coolercontrol / openlinkhub
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
sudo apt install jq curl ripgrep socat qt6-tools wireplumber pulseaudio-utils \
  rofi wl-clipboard cliphist libnotify-bin \
  playerctl network-manager bluez brightnessctl ddcutil \
  power-profiles-daemon upower solaar kdeconnect usbutils \
  grim slurp wf-recorder spectacle \
  nut-client liquidctl openrgb lm-sensors gh

# Optional: media visualizer for custom/cava
# sudo apt install cava

# CoolerControl — https://docs.coolercontrol.org/installation/debian.html
curl -1sLf 'https://dl.cloudsmith.io/public/coolercontrol/coolercontrol/setup.deb.sh' | sudo -E bash
sudo apt update && sudo apt install coolercontrol
sudo systemctl enable --now coolercontrold

# OpenLinkHub — .deb from GitHub releases or PPA (see upstream README)
sudo systemctl enable --now openlinkhub
```

### Example: Fedora

```bash
sudo dnf install jq curl ripgrep socat qt6-qttools wireplumber pipewire-pulse \
  rofi wl-clipboard cliphist libnotify \
  playerctl NetworkManager bluez brightnessctl ddcutil \
  power-profiles-daemon upower solaar kde-connect usbutils \
  grim slurp wf-recorder spectacle \
  nut liquidctl openrgb lm_sensors gh

# Optional: media visualizer for custom/cava
# sudo dnf install cava

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
| `WAYBAR_CAVA_BIN` | Override `cava` binary path for `custom/cava` (tests / custom installs) |

**Updates backends** (`custom/updates`): prefer `checkupdates` (Arch) → `apt` → `dnf`; Flatpak is additive. AUR/`paru` only on the Arch path when `enable_aur` is set — never hard-required. Review click uses `apps.paru_update` / `apt_update` / `dnf_update` when set, else a terminal with the matching upgrade command.

**Capture dirs**: defaults are `${XDG_PICTURES_DIR:-~/Pictures}/Screenshots` and `${XDG_VIDEOS_DIR:-~/Videos}/Screenrecordings` (settings `capture.*_dir` null, or set explicitly e.g. `/mnt/media/…` on a media host). Env overrides above win over settings.

**Desktop apps**: window switcher and KDE notification icons walk `$XDG_DATA_HOME/applications`, each `$XDG_DATA_DIRS/…/applications`, then Flatpak export dirs.