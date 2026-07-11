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
	"$WAYBAR_SCRIPTS/infra/listener-ctl.sh" start "$script" "$lock_name"
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
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

config_inputs_newer_than() {
	local stamp="$1"
	local f
	[ -f "$stamp" ] || return 0
	for f in \
		"$WAYBAR_HOME/data/waybar-settings.jsonc" \
		"$WAYBAR_HOME/data/waybar-settings.json" \
		"$WAYBAR_HOME/data/network-interfaces.json" \
		"$WAYBAR_HOME/data/dock-apps.json" \
		"$WAYBAR_HOME/data/workspace-desktops.json" \
		"$WAYBAR_HOME/data/workspace-glyphs.json" \
		"$WAYBAR_HOME/data/workspace-bar.json" \
		"$WAYBAR_SCRIPTS/generate/generate-settings.sh" \
		"$WAYBAR_SCRIPTS/generate/generate-module-configs.sh" \
		"$WAYBAR_SCRIPTS/generate/generate-compositor-modules.sh" \
		"$WAYBAR_SCRIPTS/generate/generate-dock-modules.sh" \
		"$WAYBAR_SCRIPTS/generate/generate-network-modules.sh" \
		"$WAYBAR_SCRIPTS/generate/generate-workspaces-css.sh"
	do
		[ -f "$f" ] || continue
		[ "$f" -nt "$stamp" ] && return 0
	done
	# Missing generated outputs force regen
	for f in \
		"$WAYBAR_HOME/includes/bar-defaults.generated.jsonc" \
		"$WAYBAR_HOME/modules/workspaces.generated.jsonc" \
		"$WAYBAR_HOME/modules/system.generated.jsonc"
	do
		[ -f "$f" ] || return 0
	done
	return 1
}

# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# Drop stale session cache so launch always re-detects (Plasma ↔ Hyprland switch).
rm -f "${XDG_RUNTIME_DIR:-/tmp}/waybar-compositor" 2>/dev/null || true
unset WAYBAR_COMPOSITOR
launch_compositor="$(detect_compositor)"
export WAYBAR_COMPOSITOR="$launch_compositor"

regen_stamp="${XDG_CACHE_HOME}/waybar/generated.stamp"
comp_stamp="${XDG_CACHE_HOME}/waybar/generated-compositor"
mkdir -p "${XDG_CACHE_HOME}/waybar"

need_regen=0
if config_inputs_newer_than "$regen_stamp"; then
	need_regen=1
elif [ ! -f "$comp_stamp" ] || [ "$(cat "$comp_stamp" 2>/dev/null || true)" != "$launch_compositor" ]; then
	# Desk/hypr modules are compositor-specific; force regen on switch.
	need_regen=1
fi

if [ "$need_regen" -eq 1 ]; then
	if [ -x "$WAYBAR_SCRIPTS/generate/generate-settings.sh" ]; then
		"$WAYBAR_SCRIPTS/generate/generate-settings.sh"
	fi

	if [ -x "$WAYBAR_SCRIPTS/generate/generate-compositor-modules.sh" ]; then
		"$WAYBAR_SCRIPTS/generate/generate-compositor-modules.sh"
	fi

	if [ -x "$WAYBAR_SCRIPTS/generate/generate-workspaces-css.sh" ]; then
		"$WAYBAR_SCRIPTS/generate/generate-workspaces-css.sh"
	fi

	# generate-settings already invokes dock/network/module generators; only
	# re-run them here when generate-settings is absent.
	if [ ! -x "$WAYBAR_SCRIPTS/generate/generate-settings.sh" ]; then
		if [ -x "$WAYBAR_SCRIPTS/generate/generate-dock-modules.sh" ]; then
			"$WAYBAR_SCRIPTS/generate/generate-dock-modules.sh"
		fi
		if [ -x "$WAYBAR_SCRIPTS/generate/generate-network-modules.sh" ]; then
			"$WAYBAR_SCRIPTS/generate/generate-network-modules.sh"
		fi
	fi

	touch "$regen_stamp"
	printf '%s\n' "$launch_compositor" >"$comp_stamp"

	if [ -x "$WAYBAR_SCRIPTS/ci/validate-generated-config.sh" ]; then
		"$WAYBAR_SCRIPTS/ci/validate-generated-config.sh"
	fi
fi

# Prime a smaller critical set asynchronously; remaining modules refresh on interval/signal.
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
cleanup_stale_tmp_files "$XDG_CACHE_HOME/waybar"
cleanup_side_info_refresh_locks

for script in \
	"$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" \
	"$WAYBAR_SCRIPTS/workspaces/active-window-status.sh" \
	"$WAYBAR_SCRIPTS/network/vpn-status.sh" \
	"$WAYBAR_SCRIPTS/media/mic-status.sh" \
	"$WAYBAR_SCRIPTS/services/desktop/nightlight-status.sh" \
	"$WAYBAR_SCRIPTS/services/devices/device-notifier-status.sh" \
	"$WAYBAR_SCRIPTS/services/sync/updates-status.sh"
do
	if [ -x "$script" ]; then
		launch_detached "$script"
	fi
done

launch_detached "$WAYBAR_SCRIPTS/network/network-interface-status.sh" --refresh
launch_detached "$WAYBAR_SCRIPTS/system/brightness-status.sh" --refresh

# Clear any leftover listeners, then start fresh after waybar can accept signals.
"$WAYBAR_SCRIPTS/infra/listener-ctl.sh" stop-all >/dev/null 2>&1 || true
(
	sleep 1.5
	if [ -x "$WAYBAR_SCRIPTS/listeners/privacy-listener.sh" ]; then
		start_waybar_listener "$WAYBAR_SCRIPTS/listeners/privacy-listener.sh" privacy
	fi

	case "$launch_compositor" in
		kde)
			if [ -x "$WAYBAR_SCRIPTS/listeners/active-window-listener-kde.py" ]; then
				start_waybar_listener "$WAYBAR_SCRIPTS/listeners/active-window-listener-kde.py" kde-activewindow
			fi
			;;
		hyprland)
			if [ -x "$WAYBAR_SCRIPTS/listeners/workspaces-hyprland-listener.sh" ]; then
				start_waybar_listener "$WAYBAR_SCRIPTS/listeners/workspaces-hyprland-listener.sh" hypr-workspaces
			fi
			;;
	esac

	if [ -x "$WAYBAR_SCRIPTS/listeners/device-notifier-listener.sh" ]; then
		start_waybar_listener "$WAYBAR_SCRIPTS/listeners/device-notifier-listener.sh" device-notifier
	fi
) &

if [ -f "$XDG_CACHE_HOME/waybar/system-metrics.json" ]; then
	launch_detached "$WAYBAR_SCRIPTS/infra/metrics-icons-build.sh"
fi

drop_patterns="$WAYBAR_SCRIPTS/infra/waybar-journal-drop.rg"
log_file="$XDG_CACHE_HOME/waybar/waybar.log"
mkdir -p "$XDG_CACHE_HOME/waybar"
: >"$log_file"

if [[ -f "$drop_patterns" ]] && command -v rg >/dev/null 2>&1; then
	exec /usr/bin/waybar "$@" \
		2> >(
			rg -v -f "$drop_patterns" | tee "$log_file" >&2
		)
fi

exec /usr/bin/waybar "$@" 2> >(tee "$log_file" >&2)
