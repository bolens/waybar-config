#!/usr/bin/env bash
# Keep launcher process footprint minimal for service restarts.
set -euo pipefail

theme_has_arrow() {
	local theme_name="$1"
	local base
	for base in "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons; do
		if [[ -e "$base/$theme_name/cursors/arrow" ]]; then
			return 0
		fi
	done
	return 1
}

launch_detached() {
	if command -v setsid >/dev/null 2>&1; then
		setsid -f "$@" >/dev/null 2>&1 < /dev/null || true
		return
	fi
	nohup "$@" >/dev/null 2>&1 &
}

start_waybar_listener() {
	script="$1"
	lock_name="$2"
	"$WAYBAR_SCRIPTS/listener-ctl.sh" start "$script" "$lock_name"
}

export XCURSOR_PATH="${XCURSOR_PATH:-$HOME/.icons:$HOME/.local/share/icons:/usr/share/icons}"

# Force a stable cursor theme for Waybar. Some theme names intermittently fail
# to resolve 'arrow' under this user service environment even when installed.
export XCURSOR_THEME="default"

if ! theme_has_arrow "$XCURSOR_THEME"; then
	export XCURSOR_THEME="Adwaita"
fi

if [[ -z "${XCURSOR_SIZE:-}" ]]; then
	if command -v gsettings >/dev/null 2>&1; then
		cursor_size="$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || true)"
		if [[ "$cursor_size" =~ ^[0-9]+$ ]]; then
			export XCURSOR_SIZE="$cursor_size"
		fi
	fi
	if [[ -z "${XCURSOR_SIZE:-}" ]]; then
		export XCURSOR_SIZE="24"
	fi
fi

export WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
export WAYBAR_SCRIPTS="$WAYBAR_HOME/scripts"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/waybar-settings.sh"

if [ -x "$WAYBAR_SCRIPTS/generate-settings.sh" ]; then
	"$WAYBAR_SCRIPTS/generate-settings.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/generate-compositor-modules.sh" ]; then
	"$WAYBAR_SCRIPTS/generate-compositor-modules.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/generate-workspaces-css.sh" ]; then
	"$WAYBAR_SCRIPTS/generate-workspaces-css.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/generate-dock-modules.sh" ]; then
	"$WAYBAR_SCRIPTS/generate-dock-modules.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/generate-network-modules.sh" ]; then
	"$WAYBAR_SCRIPTS/generate-network-modules.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/validate-generated-config.sh" ]; then
	"$WAYBAR_SCRIPTS/validate-generated-config.sh"
fi

# Prime expensive module caches asynchronously so Waybar can render immediately.
. "$WAYBAR_SCRIPTS/waybar-cache-helpers.sh"
cleanup_stale_tmp_files "$XDG_CACHE_HOME/waybar"
cleanup_side_info_refresh_locks

for script in \
	"$WAYBAR_SCRIPTS/system-metrics-collector.sh" \
	"$WAYBAR_SCRIPTS/docker-status.sh" \
	"$WAYBAR_SCRIPTS/vpn-status.sh" \
	"$WAYBAR_SCRIPTS/tailscale-status.sh" \
	"$WAYBAR_SCRIPTS/runtimes-status.sh" \
	"$WAYBAR_SCRIPTS/updates-status.sh" \
	"$WAYBAR_SCRIPTS/nightlight-status.sh" \
	"$WAYBAR_SCRIPTS/mic-status.sh" \
	"$WAYBAR_SCRIPTS/active-window-status.sh" \
	"$WAYBAR_SCRIPTS/side-info-system-tab.sh" \
	"$WAYBAR_SCRIPTS/side-info-network-tab.sh" \
	"$WAYBAR_SCRIPTS/disk-status.sh" \
	"$WAYBAR_SCRIPTS/kdeconnect-status.sh" \
	"$WAYBAR_SCRIPTS/weather-status.sh" \
	"$WAYBAR_SCRIPTS/systemd-status.sh" \
	"$WAYBAR_SCRIPTS/github-status.sh" \
	"$WAYBAR_SCRIPTS/uptime-status.sh" \
	"$WAYBAR_SCRIPTS/psu-status.sh" \
	"$WAYBAR_SCRIPTS/device-battery-status.sh" \
	"$WAYBAR_SCRIPTS/fans-status.sh" \
	"$WAYBAR_SCRIPTS/libredefender-status.sh" \
	"$WAYBAR_SCRIPTS/chkrootkit-status.sh" \
	"$WAYBAR_SCRIPTS/device-notifier-status.sh" \
	"$WAYBAR_SCRIPTS/touchpad-status.sh" \
	"$WAYBAR_SCRIPTS/vaults-status.sh"
do
	if [ -x "$script" ]; then
		launch_detached "$script"
	fi
done

launch_detached "$WAYBAR_SCRIPTS/network-interface-status.sh" --refresh

launch_detached env NUT_TARGET="$(waybar_services_nut_target)" "$WAYBAR_SCRIPTS/ups-status.sh"
launch_detached "$WAYBAR_SCRIPTS/brightness-status.sh" --refresh

# Start background listeners after a short delay to ensure Waybar is fully
# initialized and has registered its signal handlers before receiving updates.
(
	sleep 1.5
	if [ -x "$WAYBAR_SCRIPTS/privacy-listener.sh" ]; then
		start_waybar_listener "$WAYBAR_SCRIPTS/privacy-listener.sh" privacy
	fi

	if [ -x "$WAYBAR_SCRIPTS/active-window-listener-kde.py" ]; then
		start_waybar_listener "$WAYBAR_SCRIPTS/active-window-listener-kde.py" kde-activewindow
	fi

	if [ -x "$WAYBAR_SCRIPTS/workspaces-hyprland-listener.sh" ]; then
		start_waybar_listener "$WAYBAR_SCRIPTS/workspaces-hyprland-listener.sh" hypr-workspaces
	fi

	if [ -x "$WAYBAR_SCRIPTS/device-notifier-listener.sh" ]; then
		start_waybar_listener "$WAYBAR_SCRIPTS/device-notifier-listener.sh" device-notifier
	fi
) &

if [ -f "$XDG_CACHE_HOME/waybar/system-metrics.json" ]; then
	launch_detached "$WAYBAR_SCRIPTS/metrics-icons-build.sh"
fi

drop_patterns="$WAYBAR_HOME/scripts/waybar-journal-drop.rg"
log_file="$XDG_CACHE_HOME/waybar/waybar.log"
mkdir -p "$XDG_CACHE_HOME/waybar"
> "$log_file"

if [[ -f "$drop_patterns" ]] && command -v rg >/dev/null 2>&1; then
	exec /usr/bin/waybar "$@" \
		2> >(
			rg -v -f "$drop_patterns" | tee "$log_file" >&2
		)
fi

exec /usr/bin/waybar "$@" 2> >(tee "$log_file" >&2)
