# Legacy generator contracts

Inspected revision: `cf333defce09672c36774720d209531ffe891e2c` plus the current
FR-015 through FR-018 corrective changes. All 24 generator scripts were read. Runtime
helpers and external services have separate acceptance boundaries.

The source is settings JSONC and allowlisted data manifests. Generators write
compiled JSON/JSONC/CSS, not the running bar. Use `make generate` for artifacts.
Most emitters use Bash strict mode and jq, but output writes are not a multi-file
transaction. A failure can leave a partially regenerated tree. Missing-input and
optional-prefetch behavior differs by emitter; absence is not proof of success.

| Contract | Generator under `scripts/generate/` | Inputs | Output behavior |
| --- | --- | --- | --- |
| GG-001 | `generate-settings.sh` | JSONC settings | Compiled settings, bars, groups, includes and layouts; inserts album art/cava/carousel transforms and invokes module/CSS emitters. |
| GG-002 | `generate-active-window-modules.sh` | active_window.per_output | Active-window stream and switcher commands; quote output argument and avoid double-escaping script markup. |
| GG-003 | `generate-audio-modules.sh` | audio, bluetooth, visual.album_art | Media, volume, microphone, visualizer, Bluetooth and optional cover module/CSS with command overrides. |
| GG-004 | `generate-center-extras-modules.sh` | keyboard, gamemode, signals | Keyboard layout, game mode and keybind-hint status/click wiring. |
| GG-005 | `generate-clock-modules.sh` | clocks, locale, theme colors | Clock format and calendar labels/colors; explicit settings override detected locale defaults. |
| GG-006 | `generate-compositor-modules.sh` | compositor, workspaces, layouts | Native Hyprland overlay or empty overlay, workspace slots, desk group and top layout; count falls back through manifest/query/default and caps at ten. |
| GG-007 | `generate-dock-modules.sh` | dock-apps manifest, dock/drawers settings | Ordered launcher modules, drawer group and bottom layout; FR-016 validates IDs before output replacement and JSON-encodes drawer classes; FR-017 preserves explicit false settings. |
| GG-008 | `generate-dock-windows-modules.sh` | dock_windows, signals, intervals | Window slots and group with count up to sixteen; status gets output argument, clicks resolve active output themselves. |
| GG-009 | `generate-drawers-modules.sh` | groups, drawers, dock/network manifests | Thirteen drawer handles, content labels and idle inhibitor. Mirrors media/carousel transforms and escapes Pango markup plus format braces. |
| GG-010 | `generate-hypr-tools-modules.sh` | hypr_tools, intervals | Notification/light/voice modules with tool-specific status wrappers and configured click commands. |
| GG-011 | `generate-network-modules.sh` | network-interfaces manifest, intervals | Bandwidth, bond and per-interface modules. FR-015 quotes interface arguments at shell boundaries while preserving native interface and tooltip values. |
| GG-012 | `generate-network-custom-modules.sh` | network, services, intervals, signals | VPN, Tailscale, i2pd, Yggdrasil and IPFS modules with refresh/click overrides. |
| GG-013 | `generate-privacy-modules.sh` | privacy intervals and signal | Five status/click channels: screenshare, webcam, audio input/output and location. |
| GG-014 | `generate-tray-modules.sh` | tray | Native tray icon size and spacing. |
| GG-015 | `generate-utilities-modules.sh` | apps and domain settings | Notifications, capture, nightlight, clipboard, brightness, power/device/service utilities, weather and pomodoro; optional per-output arguments for capture/brightness. |
| GG-016 | `generate-animations-css.sh` | visual.animations, resolved colors | GTK-compatible workspace pulse, critical breathe and idle glow. Forced reduced motion suppresses keyframes. |
| GG-017 | `generate-dock-appicon-css.sh` | icons.appicon, dock-apps | Launcher image/layout/hover CSS and label hitboxes. Optional prefetch tolerates missing icons; absolute file URLs support style reload. |
| GG-018 | `generate-dock-windows-css.sh` | dock slots, appicon settings/manifest | Window-slot hit/active/hidden styling and per-app image rules; resets the runtime-rule stub for later runtime additions. |
| GG-019 | `generate-drawers-css.sh` | CSS selector registry | Drawer shell/handle/hidden-child layout without container pills. |
| GG-020 | `generate-groups-css.sh` | CSS selector registry | Cluster chrome and adjoining child border/margin treatment. |
| GG-021 | `generate-reduced-motion-css.sh` | reduced-motion mode/environment | Deterministic generation honors forced modes but suppresses automatic host probing unless explicitly enabled; delegates runtime override generation. |
| GG-022 | `generate-submap-css.sh` | hypr_tools.submap_per_output, output list | Optional per-output presentation selectors for session-global submap state, with sanitized output classes and fallback names. |
| GG-023 | `generate-theme-tokens.sh` | theme, bar chrome, selector registry | Concrete GTK tokens, shared pills and semantic status colors. Preserves existing wallpaper overlay and imports it only in wallpaper mode. |
| GG-024 | `generate-workspaces-css.sh` | workspace-bar manifest, settings, colors | Workspace slot hitboxes, active pills and spacing; preserves explicit false fit_content and caps slot count through the shared helper. |

## Validation and unresolved boundaries

Existing generator suites exercise settings overrides, output wiring, CSS
compatibility, slot behavior, icon fallback and reduced motion. The current
network suite also checks ten shell command boundaries with disposable stubs.
Those fixtures do not verify all live desktop integrations or physical devices.

Generated icon CSS embeds host paths. The drift checker normalizes only the
file-URL prefix for comparison. Real network module changes still require new
committed generated output. Icon prefetch may report missing optional assets.

Dock boundary and full drawer suites pass for FR-016/FR-017. The shared-library
suite passes FR-018: theme preset comments and quoted URLs retain base colors
and explicit settings overrides. System Python provides GTK3, and its full CSS
parse passes. Runtime helper inspection and final delivery remain incomplete.
