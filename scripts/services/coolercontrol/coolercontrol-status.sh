#!/usr/bin/env bash
# Waybar status for CoolerControl daemon (coolercontrold).
# Auth: Bearer token preferred; ui_pass used only if token missing or fails.
# Write probe (PATCH /settings {}): class includes writable|readonly.
# Shows active mode when configured; scroll/right-click cycle via coolercontrol-click.sh.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/coolercontrol-status.json"
lock_dir="$cache_dir/coolercontrol-status.lock.d"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
ttl="$(waybar_module_interval coolercontrol 10)"
stale_lock_ttl=20
api_py="$WAYBAR_SCRIPTS/services/coolercontrol/coolercontrol-api.py"

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰔏 --" "Initializing CoolerControl..." "normal"
  exit 0
fi

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

write_cache_and_exit() {
  json="$1"
  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  if printf '%s\n' "$json" >"$tmp_cache" 2>/dev/null; then
    mv -f "$tmp_cache" "$cache_file" 2>/dev/null || rm -f "$tmp_cache" 2>/dev/null || true
  fi
  exit 0
}

emit_disconnected() {
  write_cache_and_exit "$(emit_waybar_json "" "$1" "disconnected")"
}

emit_cc_json() {
  # $1 text $2 tooltip $3 primary class $4 optional capability class (writable|readonly)
  local text="$1" tooltip="$2" primary="$3" cap="${4:-}"
  local tooltip_expanded esc_text esc_tooltip
  tooltip_expanded=$(printf '%b' "$tooltip")
  esc_text=$(escape_markup "$text")
  esc_tooltip=$(escape_markup "$tooltip_expanded")
  if [ -n "$cap" ]; then
    jq -cn \
      --arg text "$esc_text" \
      --arg tooltip "$esc_tooltip" \
      --arg primary "$primary" \
      --arg cap "$cap" \
      '{text:$text, tooltip:$tooltip, class:[$primary, $cap]}'
  else
    jq -cn \
      --arg text "$esc_text" \
      --arg tooltip "$esc_tooltip" \
      --arg class "$primary" \
      '{text:$text, tooltip:$tooltip, class:$class}'
  fi
}

service_name=$(waybar_settings_get '.services.coolercontrol.service_name' 'coolercontrold.service')
api_url=$(waybar_settings_get '.services.coolercontrol.api_url' 'http://127.0.0.1:11987')
api_url="${api_url%/}"
ui_user=$(waybar_settings_get '.services.coolercontrol.ui_user' 'CCAdmin')
ui_pass="${WAYBAR_CC_UI_PASS:-$(waybar_settings_get '.services.coolercontrol.ui_pass' '')}"
token="${WAYBAR_CC_TOKEN:-$(waybar_settings_get '.services.coolercontrol.token' '')}"
temp_warn=$(waybar_settings_get '.thresholds.coolercontrol.temp.warning' '75')
temp_crit=$(waybar_settings_get '.thresholds.coolercontrol.temp.critical' '90')

if [ -z "$token" ] || [ "$token" = "null" ] || [ "$token" = "CHANGE_ME" ]; then
  token=""
fi
if [ -z "$ui_pass" ] || [ "$ui_pass" = "null" ] || [ "$ui_pass" = "CHANGE_ME" ]; then
  ui_pass=""
fi

# Fixture / force-active path for tests
if [ -z "${WAYBAR_CC_FIXTURE_DIR:-}" ]; then
  service_active=0
  if [ "${WAYBAR_CC_FORCE_ACTIVE:-0}" = "1" ]; then
    service_active=1
  elif systemctl is-active -q "$service_name" 2>/dev/null; then
    service_active=1
  elif pgrep -x coolercontrold >/dev/null 2>&1; then
    service_active=1
  fi
  if [ "$service_active" -eq 0 ]; then
    emit_disconnected "CoolerControl daemon offline (systemctl enable --now coolercontrold)"
  fi
  if [ -z "$token" ] && [ -z "$ui_pass" ]; then
    emit_disconnected "CoolerControl credentials missing — sudo scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh"
  fi
fi

bundle=$(
  WAYBAR_CC_API_URL="$api_url" \
    WAYBAR_CC_UI_USER="$ui_user" \
    WAYBAR_CC_UI_PASS="$ui_pass" \
    WAYBAR_CC_TOKEN="$token" \
    WAYBAR_CC_FIXTURE_DIR="${WAYBAR_CC_FIXTURE_DIR:-}" \
    python3 "$api_py" fetch-bundle 2>/dev/null || true
)

if [ -z "$bundle" ] || ! printf '%s' "$bundle" | jq -e '.ok == true' >/dev/null 2>&1; then
  emit_disconnected "CoolerControl API unreachable or auth failed (need POST /login or Bearer token)"
fi

parsed=$(
  BUNDLE_JSON="$bundle" TEMP_WARN="$temp_warn" TEMP_CRIT="$temp_crit" python3 <<'PY'
import json, os, sys

bundle = json.loads(os.environ["BUNDLE_JSON"])
warn = float(os.environ.get("TEMP_WARN", "75"))
crit = float(os.environ.get("TEMP_CRIT", "90"))

status = bundle.get("status") or {}
devices = bundle.get("devices") or {}
modes_obj = bundle.get("modes") or {}
active = bundle.get("modes_active") or {}
write_access = bundle.get("write_access")  # True/False/None

names = {}
for dev in devices.get("devices") or []:
    if isinstance(dev, dict) and dev.get("uid"):
        names[str(dev["uid"])] = str(dev.get("name") or dev["uid"])

device_list = status.get("devices") if isinstance(status, dict) else None
if not isinstance(device_list, list):
    print("ERR")
    sys.exit(0)

temps, rpms, duties, watts = [], [], [], []
for dev in device_list:
    if not isinstance(dev, dict):
        continue
    uid = str(dev.get("uid") or "")
    d_type = str(dev.get("type") or dev.get("d_type") or "")
    dname = names.get(uid) or (f"{d_type}:{uid[:8]}" if d_type else uid[:12] or "device")
    history = dev.get("status_history") or []
    if not isinstance(history, list) or not history:
        continue
    latest = history[-1]
    if not isinstance(latest, dict):
        continue
    for t in latest.get("temps") or []:
        if isinstance(t, dict) and isinstance(t.get("temp"), (int, float)):
            temps.append((f"{dname}/{t.get('name') or 'temp'}", float(t["temp"])))
    for ch in latest.get("channels") or []:
        if not isinstance(ch, dict):
            continue
        label = f"{dname}/{ch.get('name') or 'ch'}"
        if isinstance(ch.get("rpm"), (int, float)):
            rpms.append((label, float(ch["rpm"])))
        if isinstance(ch.get("duty"), (int, float)):
            duties.append((label, float(ch["duty"])))
        if isinstance(ch.get("watts"), (int, float)):
            watts.append((label, float(ch["watts"])))

modes = [m for m in (modes_obj.get("modes") or []) if isinstance(m, dict) and m.get("uid")]
mode_names = {str(m["uid"]): str(m.get("name") or m["uid"]) for m in modes}
cur_uid = active.get("current_mode_uid") if isinstance(active, dict) else None
cur_name = mode_names.get(str(cur_uid), None) if cur_uid else None

hot = max((t for _, t in temps), default=None)
primary = "normal"
if hot is not None:
    if hot >= crit:
        primary = "critical"
    elif hot >= warn:
        primary = "warning"

if hot is not None:
    text = f"󰔏 {hot:.0f}°"
elif rpms:
    text = f"󰔏 {max(r for _, r in rpms):.0f}"
elif watts:
    text = f"󰔏 {max(w for _, w in watts):.0f}W"
elif cur_name:
    text = f"󰔏 {cur_name}"
else:
    text = "󰔏 on"

cap = ""
if write_access is True:
    cap = "writable"
elif write_access is False:
    cap = "readonly"

lines = ["CoolerControl"]
if cur_name:
    lines += ["", f"Mode: {cur_name}"]
elif modes:
    lines += ["", "Mode: (none active)"]
if write_access is True:
    lines.append("Token: write")
elif write_access is False:
    lines.append("Token: read-only")
else:
    lines.append("Token: capability unknown")

if temps:
    lines += ["", "Temperatures"]
    for n, t in sorted(temps, key=lambda x: -x[1])[:12]:
        lines.append(f"  {n}: {t:.1f}°C")
if rpms:
    lines += ["", "Fans / pumps"]
    for n, r in sorted(rpms, key=lambda x: -x[1])[:10]:
        lines.append(f"  {n}: {r:.0f} RPM")
if duties:
    lines += ["", "Duty"]
    for n, d in sorted(duties, key=lambda x: -x[1])[:8]:
        lines.append(f"  {n}: {d:.0f}%")

lines += ["", "Left: open UI · Middle: refresh"]
if write_access is True and modes:
    lines.append("Scroll/Right: cycle modes · Right-menu: pick mode")
elif write_access is True:
    lines.append("Write token (create Modes in UI to enable cycling)")
elif write_access is False:
    lines.append("Read-only token — mode controls disabled")
else:
    lines.append("Right: restart daemon")

print("OK")
print(text)
print(primary)
print(cap)
print("\n".join(lines))
PY
)

status_line=$(printf '%s\n' "$parsed" | sed -n '1p')
if [ "$status_line" != "OK" ]; then
  emit_disconnected "CoolerControl status parse failed (unexpected /status shape)"
fi

text=$(printf '%s\n' "$parsed" | sed -n '2p')
primary=$(printf '%s\n' "$parsed" | sed -n '3p')
cap=$(printf '%s\n' "$parsed" | sed -n '4p')
tooltip=$(printf '%s\n' "$parsed" | sed -n '5,$p')

json=$(emit_cc_json "$text" "$tooltip" "$primary" "$cap")
write_cache_and_exit "$json"
