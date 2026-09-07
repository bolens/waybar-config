# Legacy runtime contracts

Inspected source: `cf333defce09672c36774720d209531ffe891e2c`, with corrective
requirements FR-019 through FR-028. This register covers the helpers listed
below, including both dock-window libraries and all ten KDE listener package
files. Most runtime entry points still require inspection. It is not a
completed runtime audit.

## Shared helper ownership

Paths below are relative to `scripts/lib/`. Observed behavior does not imply
that external services, hardware, sessions or credentials were exercised.

| Contract | Source | Observed contract and acceptance boundary |
| --- | --- | --- |
| RH-001 | `appicon-lib.sh` | Optional binary discovery, binary/icon miss TTLs, offline resolution and raster materialization. Existing cached images are reused; unresolved icons retain glyph fallback. |
| RH-002 | `xdg-applications.sh` | Ordered unique user/system/Flatpak application directories. Discovery includes directories that do not yet exist. |
| RH-003 | `xdg-icons-lib.sh` | Desktop class/name/executable maps and fallback guessing, shared by the window switcher and notification menu. FR-019 fixes cold parsing and warm map scope. Cache freshness uses application-directory mtimes. |
| RH-004 | `brightness-lib.sh` | Per-output cache and explicit target selection, internal-panel backlight preference, external DDC fallback, gaming-mode polling suppression and disabled output when no device is available. FR-022 fixes helper loading; no physical control was tested. |
| RH-005 | `capture-lib.sh` | Environment/settings/XDG capture-directory precedence, compositor/backend selection, mode normalization, filename construction, recording PID/metadata status and clipboard helpers. Recording liveness is a PID probe, not process-identity proof. |
| RH-006 | `gtk_popup_helpers.py` | Best-effort pointer location and public-IP lookup with bounded HTTP attempts. Interface-bound lookup reports its result without proving VPN bypass. No external IP service was queried by this audit. |
| RH-007 | `rofi-popup-lib.sh` | Settings-derived menu styling and row alignment. Callers supply labels, widths and optional theme overrides. |
| RH-008 | `system-metrics-cpu.sh` | Cached topology, two-sample CPU usage and cached sensor selection from supported hwmon names or thermal fallback. Missing temperature is represented as zero. |
| RH-009 | `system-metrics-gpu.sh` | NVIDIA PCI discovery and AMD hwmon/VRAM/temperature collection. AMD busy percentage remains zero when unavailable. Source inspection does not validate physical sensor readings. |
| RH-010 | `system-metrics-top.sh` | Three CPU/memory process labels, cached for 24 seconds and replaced through temporary files. FR-021 ensures JSON string encoding before the collector consumes these arrays. |
| RH-011 | `unicode-animations-lib.sh` | Named frames, reduced-motion/background bypass and animated child output. FR-020 preserves the child exit status after cleanup, enabling weather provider fallback. |
| RH-012 | `theme-wallpaper-lib.sh` | Explicit/output/compositor/global wallpaper selection, optional palette backends, normalization and output-scoped CSS. Backend execution can update backend-owned caches and is an operational boundary. |
| RH-013 | `settings-bool-lib.sh` | Shared true/false spellings prevent inconsistent boolean interpretation across shell callers. |
| RH-014 | `waybar-settings.sh`, `jsonc_util.py` | Settings/overlay access and shared JSONC parsing. FR-010 preserves quoted delimiters; FR-011 redacts structured secret values. MCP write rules are specified separately. |
| RH-015 | `waybar-signal.sh` | Resolve named signals through settings and send the corresponding Waybar refresh signal. Live signaling was not exercised. |
| RH-016 | `waybar-cache-helpers.sh` | Shared cache age, stale locks, background refresh, temporary cache replacement, escaped Waybar JSON and thresholds. Callers own their paths and refresh commands. |
| RH-017 | `compositor-gate.sh`, `compositor-session.sh` | Session selection and compositor-specific command gating, with explicit environment and test overrides. |
| RH-018 | `app-open-lib.sh` | Shared application-opening helper used by configured launch actions. Source validation does not authorize launching applications during tests. |
| RH-019 | `clipboard-lib.sh` | Shared clipboard backend/status helpers. Fixture evidence excludes the user's clipboard contents. |
| RH-020 | `notifications-lib.sh` | Shared notification backend selection and status helpers; session adapters retain separate evidence limits. |
| RH-021 | `network-ip-lib.sh` | Shared interface/IP formatting used by network status. No network configuration changes are part of this baseline. |
| RH-022 | `output-lib.sh` | Output discovery and sanitized CSS/output identifiers, including explicit fixture output lists. |
| RH-023 | `gauge-lib.sh` | Bounded textual gauge rendering for status modules. Presentation does not establish the accuracy of upstream measurements. |
| RH-024 | `ddcutil-lock.sh` | Shared DDC command serialization. Current callers suppress unavailable-device failures; no monitor operation was performed. |
| RH-025 | `theme-colors-lib.sh` | Theme color resolution and settings overrides. FR-018 uses the shared JSONC parser for preset metadata and colors. |
| RH-026 | `waybar-locale-lib.sh`, `locale_temp.py` | Locale-aware temperature/measurement formatting, including shell/Python parity fixtures. |
| RH-027 | `notify_markup.py` | Notification text markup handling. Source and synthetic-text checks do not read live notification content. |
| RH-028 | `reduced-motion-lib.sh` | Explicit settings/environment overrides, optional session probes and generated CSS override. Generation suppresses automatic host probing by default. |
| RH-029 | `css-selectors-lib.sh` | Shared selector sets used by theme, group and drawer generators, avoiding divergent generated selector ownership. |
| RH-030 | `waybar-systemd-scan-lib.sh` | Cached scan status, timer timestamps, active-scan frames and background completion refresh. This helper reports unit state; it does not run a security scan. |
| RH-031 | `dock-windows-kde-lib.sh`, `dock-windows-kde-lib.py` | Parse WindowsRunner literals, enrich class/output metadata, filter chrome, bind output-specific slots and resolve icon keys. Missing screen metadata retains all windows; runtime CSS additions are lock-serialized and limited to valid app keys. Existing dock suites use literal/geometry fixtures. |
| RH-032 | `kde_listener/active_window.py`, `titles.py` | Debounced active titles, per-output/global caches, desktop mapping and KWin script lifecycle. Script loading is operational and was not invoked against the running compositor. |
| RH-033 | `kde_listener/clipboard.py` | Clipboard event threads write status through a shared JSON writer also used for notification history/status. FR-023 gives each write a unique temporary file. Concurrent completion order is not a promise of latest-event ordering. |
| RH-034 | `kde_listener/notifications.py` | Parse Notify/reply/closed messages, correlate IDs, retain up to 50 history records, track unread count and render escaped recent summaries. Expired notifications remain in history until clearing. |
| RH-035 | `kde_listener/refreshers.py` | Network debounce and pending refresh handling for network, KDE Connect and battery changes. Subprocess completion and GLib scheduling remain distinct from cache-write atomicity. |
| RH-036 | `kde_listener/compositor.py`, `lock.py`, `paths.py`, `signals.py`, `__init__.py` | Session gating, process-lock directory, script-root resolution and settings-based signal offsets. Stale-lock and live D-Bus behavior were inspected, not exercised against the user's session. |

## Runtime entry points inspected

`services/apps/weather-status.sh` selects configured Open-Meteo/wttr providers,
resolves configured or cached coordinates, validates provider payloads, formats
locale-aware forecasts and preserves a previous cache on transient failures.
The real animation wrapper is covered with stub HTTP: Open-Meteo failure must
reach wttr. Successful foreground animation output and final weather JSON share
the output stream. Fixtures do not contact geolocation or weather services.

`listeners/active-window-listener-kde.py` composes the mixins, initializes
cache paths and subscriptions, starts monitoring and cleans up its KWin script
and monitor process. Native fixtures import helpers with stub GI modules;
they do not instantiate a live session listener.

`network/network-interface-status.sh` refreshes manifest-selected interfaces,
tracks bond visibility and serves cached status. `network/tailscale-status.sh`
reports backend, host, peers and health. `network/vpn-status.sh` combines
NetworkManager and optional overlay-VPN status into a tunnel count. FR-024
through FR-028 cover empty fields, configured interface names and disconnected
state matching. Native suites use stub commands and disposable caches.

`infra/listener-ctl.sh` starts/stops named listener services, with detached
process fallback when the user service manager is unavailable. Its stop path
trusts a cached PID and can escalate to SIGKILL. This audit did not run it on
live listeners. Process-identity and stale-lock behavior need further validation.

All five `capture/` entry points were inspected: color picker, screenshot
click/status and recording click/status. Backend commands are operational.
The screenshot failure fixture covers FR-027. Recording stop currently trusts
cached process liveness, and startup notification does not prove successful
recording. Those lifecycle boundaries require further validation.

All eight `media/` entry points were inspected: static previous/next glyphs,
audio settings/output selection, microphone toggle/status, album-art caching,
cava streaming and MPRIS scrolling. FR-028 prevents unconfirmed microphone
state notifications. Album art supports file/HTTP inputs and explicit cache
cleanup, cava caps bars/frame rate and suppresses duplicate output, and MPRIS
escapes markup with scrolling/static fallbacks. Streaming restart/termination
behavior and optional backend execution still need dedicated validation.

## Verification and remaining work

The existing `lib-utils` suite covers FR-019 through FR-028 with disposable
files and stub commands. The weather suite covers FR-020 through the real
wrapper; GitHub status regressions also pass. These checks supplement the
existing generator and theme suites, not live desktop acceptance.

The remaining status/click entry points and other listener entry points are
still pending. Each needs source ownership, observable
behavior and acceptance evidence before the exhaustive task can close.

## Network popups and listener lifecycle

The detailed pass read all Ethernet and VPN popup source, Bluetooth and Wi-Fi
menus, and the five consumers of `dock-windows-listener-lock.sh`.

| Surface | Observed contract and verification boundary |
| --- | --- |
| Ethernet popup | Query interface/profile/bond details with bounded subprocess calls, cache public IPs for the popup lifetime, and toggle details and sensitive addresses. FR-030 covers literal label text and DNS masking. Geometry and actual network queries remain source-reviewed. |
| VPN popup | Query Tailscale, Netbird, NetworkManager and ZeroTier concurrently, then display details with optional sensitive reveal. FR-029/030 cover missing Tailscale and literal provider values. No real provider commands ran in the UI fixture. |
| Bluetooth menu | List controller/device status, toggle power/discoverability, and select connect/disconnect or a settings application. Rofi state carries the detail toggle. Controller address parsing and delimiter-bearing device names still need boundary verification. |
| Wi-Fi menu | Cache external IP/latency, list and deduplicate scan results, retain detail/sensitive state in Rofi, and launch an explicit selected connection. Sensitive reveal uses two steps. Escaped delimiters and formatted SSID round trips still need boundary verification. |
| Shared listener lock | Single-instance lock with optional cleanup hook. FR-032 covers termination and ownership release. Pipeline descendants in device/workspace listeners need additional lifecycle verification. |
| Album-art listener | Metadata events and a periodic fallback refresh the cache and signal changed output. Missing playerctl uses slow polling. |
| Privacy listener | Audio events and periodic fallback refresh privacy and microphone caches. |
| VPN/Tailscale listener | NetworkManager events and periodic fallback refresh status and signal changed output. |
| Device listener | Block-device events invalidate the device status module. |
| Hyprland workspace listener | Resolve the compositor event socket and update workspace, keyboard, active-window and dock state by event type. |

These additions do not close the remaining runtime audit task. Cava startup and
termination, recording process ownership, and the menu/lifecycle boundaries above
remain explicit follow-up work.
