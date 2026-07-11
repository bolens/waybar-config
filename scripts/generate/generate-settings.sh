#!/usr/bin/env bash
# Regenerate bar defaults, layouts, groups, and system modules from data/waybar-settings.jsonc (compiled to .json).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
network_manifest="$WAYBAR_HOME/data/network-interfaces.json"
scripts='$WAYBAR_HOME/scripts'

bar_defaults_out="$WAYBAR_HOME/includes/bar-defaults.generated.jsonc"
top_layout_out="$WAYBAR_HOME/layouts/top-shell.generated.jsonc"
bottom_layout_out="$WAYBAR_HOME/layouts/bottom.generated.jsonc"
groups_out="$WAYBAR_HOME/modules/groups.generated.jsonc"
system_out="$WAYBAR_HOME/modules/system.generated.jsonc"

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

expand_group_modules() {
  local group_key="$1"
  jq -c --arg key "$group_key" '
    .groups[$key].modules // []
    | map(
        if . == "@network.interfaces" then
          []
        else
          .
        end
      )
    | flatten
  ' "$settings"
}

network_interface_modules() {
  if [[ ! -f "$network_manifest" ]]; then
    return 0
  fi
  jq -r '.interfaces[]?.id // empty' "$network_manifest" | while read -r id; do
    [[ -n "$id" ]] && printf 'custom/%s\n' "$id"
  done
}

build_groups_json() {
  jq -n \
    --slurpfile settings "$settings" \
    --slurpfile network "$network_manifest" \
    '
    def drawer_defaults:
      $settings[0].drawers // {};

    def drawer_for($side):
      {
        "click-to-reveal": (if drawer_defaults.click_to_reveal != null then drawer_defaults.click_to_reveal else true end),
        "transition-duration": (drawer_defaults.transition_duration // 500),
        "children-class": (drawer_defaults.children_class // "drawer-child"),
        "transition-left-to-right": (
          if $side == "right" then
            (if drawer_defaults.left_to_right.right != null then drawer_defaults.left_to_right.right else true end)
          elif $side == "left" then
            (if drawer_defaults.left_to_right.left != null then drawer_defaults.left_to_right.left else false end)
          else
            false
          end
        )
      };

    def expand_modules($mods):
      reduce $mods[] as $mod (
        [];
        if $mod == "@network.interfaces" then
          . + (
            if ($network | length) > 0 then
              ($network[0].interfaces // []) | map("custom/" + .id)
            else
              []
            end
          )
        else
          . + [$mod]
        end
      );

    ($settings[0].groups // {}) | to_entries | map(
      .key as $key
      | ("group/" + $key) as $group_id
      | {
          key: $group_id,
          value: (
            {
              orientation: "inherit"
            }
            + (if .value.drawer? then { drawer: drawer_for(.value.drawer) } else {} end)
            + { modules: expand_modules(.value.modules // []) }
          )
        }
    ) | from_entries
    '
}

build_system_json() {
  local app_open="${scripts}/tools/app-open.sh"
  local bond_iface="bond0"
  if [[ -f "$network_manifest" ]]; then
    bond_iface="$(jq -r '.bond.interface // "bond0"' "$network_manifest")"
  fi

  local libredefender_service
  libredefender_service=$(waybar_settings_get '.services.libredefender.service_name' 'libredefender-scan.service')
  local chkrootkit_service
  chkrootkit_service=$(waybar_settings_get '.services.chkrootkit.service_name' 'chkrootkit-scan.service')
  local syncthing_service
  syncthing_service=$(waybar_settings_get '.services.syncthing.service_name' 'syncthing')
  local terminal_app
  terminal_app=$(waybar_settings_get '.apps.terminal' 'ghostty')

  jq -n \
    --slurpfile settings "$settings" \
    --arg app_open "$app_open" \
    --arg scripts "$scripts" \
    --arg bond_iface "$bond_iface" \
    --arg eth_popup "python3 ${scripts}/network/ethernet-popup.py" \
    --arg libredefender_service "$libredefender_service" \
    --arg chkrootkit_service "$chkrootkit_service" \
    --arg syncthing_service "$syncthing_service" \
    --arg terminal_app "$terminal_app" \
    '
    def app($key): $settings[0].apps[$key] // "";
    def interval($key): ($settings[0].module_intervals[$key] // $settings[0].poll_intervals[$key] // 1);
    def signal($key): $settings[0].signals[$key] // null;
    def click_app($key): ($app_open + " " + app($key));
    def term_cmd($cmd): ($app_open + " " + $terminal_app + " -e " + $cmd);
    {
      "custom/cpu": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("cpu"),
        exec: ($scripts + "/system/cpu-status.sh"),
        "on-click": click_app("system_monitor"),
        "on-click-right": click_app("btop"),
        "on-click-middle": click_app("plasma_system_monitor")
      },
      "custom/gpu": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("gpu"),
        exec: ($scripts + "/system/gpu-status.sh"),
        "on-click": click_app("system_monitor"),
        "on-click-right": click_app("nvtop"),
        "on-click-middle": click_app("nvidia_smi")
      },
      "custom/memory": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("memory"),
        exec: ($scripts + "/system/memory-status.sh"),
        "on-click": click_app("system_monitor"),
        "on-click-right": click_app("btop"),
        "on-click-middle": click_app("plasma_system_monitor")
      },
      "custom/docker": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("docker"),
        exec: ($scripts + "/services/containers/docker-status.sh"),
        "on-click": click_app("lazydocker"),
        "on-click-right": ($app_open + " xdg-open " + app("portainer_url")),
        "on-click-middle": click_app("docker_ps")
      },
      "custom/system": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("system_tab"),
        exec: ($scripts + "/side-info/side-info-system-tab.sh"),
        "on-click": click_app("system_monitor"),
        "on-click-right": click_app("btop"),
        "on-click-middle": click_app("plasma_system_monitor")
      },
      "custom/network": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("network_tab"),
        exec: ($scripts + "/side-info/side-info-network-tab.sh"),
        "on-click": ($eth_popup + " " + $bond_iface),
        "on-click-right": click_app("network_editor"),
        "on-click-middle": click_app("ip_addr")
      },
      "custom/runtimes": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("runtimes"),
        exec: ($scripts + "/services/containers/runtimes-status.sh"),
        "on-click": click_app("virt_manager"),
        "on-click-right": click_app("podman_ps"),
        "on-click-middle": click_app("virsh_list")
      },
      "custom/updates": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        signal: signal("updates"),
        interval: interval("updates"),
        escape: true,
        exec: ($scripts + "/services/sync/updates-status.sh"),
        "on-click": click_app("paru_update"),
        "on-click-right": click_app("updates_review"),
        "on-click-middle": ($scripts + "/services/sync/updates-status.sh --refresh")
      },
      "custom/ups": {
        format: "{}",
        interval: interval("ups"),
        "return-type": "json",
        tooltip: true,
        exec: ($scripts + "/system/ups-status-wrapper.sh"),
        "on-click": click_app("power_settings"),
        "on-click-right": click_app("btop"),
        "on-click-middle": ($scripts + "/system/ups-status.sh --refresh")
      },
      "custom/disk": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("disk"),
        exec: ($scripts + "/system/disk-status.sh"),
        "on-click": click_app("file_manager"),
        "on-click-right": click_app("btop"),
        "on-click-middle": ($scripts + "/system/disk-status.sh --refresh")
      },
      "custom/uptime": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("uptime"),
        exec: ($scripts + "/system/uptime-status.sh"),
        "on-click": click_app("btop"),
        "on-click-right": click_app("plasma_system_monitor"),
        "on-click-middle": ($scripts + "/system/uptime-status.sh --refresh")
      },
      "custom/psu": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("psu"),
        exec: ($scripts + "/system/psu-status.sh"),
        "on-click": click_app("system_monitor"),
        "on-click-right": click_app("btop"),
        "on-click-middle": ($scripts + "/system/psu-status.sh --refresh")
      },
      "custom/fans": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("fans"),
        exec: ($scripts + "/system/fans-status.sh"),
        "on-click": click_app("nvtop"),
        "on-click-right": click_app("btop"),
        "on-click-middle": ($scripts + "/system/fans-status.sh --refresh")
      },
      "custom/libredefender": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("libredefender"),
        exec: ($scripts + "/services/security/libredefender-status.sh"),
        "on-click": ($settings[0].services.libredefender.on_click // ($app_open + " systemctl start " + $libredefender_service)),
        "on-click-right": ($settings[0].services.libredefender.on_click_right // term_cmd("journalctl -u " + $libredefender_service + " -f")),
        "on-click-middle": ($settings[0].services.libredefender.on_click_middle // ($scripts + "/services/security/libredefender-status.sh --refresh"))
      },
      "custom/chkrootkit": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("chkrootkit"),
        exec: ($scripts + "/services/security/chkrootkit-status.sh"),
        "on-click": ($settings[0].services.chkrootkit.on_click // ($app_open + " systemctl start " + $chkrootkit_service)),
        "on-click-right": ($settings[0].services.chkrootkit.on_click_right // term_cmd("journalctl -u " + $chkrootkit_service + " -f")),
        "on-click-middle": ($settings[0].services.chkrootkit.on_click_middle // ($scripts + "/services/security/chkrootkit-status.sh --refresh"))
      },
      "custom/syncthing": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("syncthing"),
        signal: signal("syncthing"),
        exec: ($scripts + "/services/sync/syncthing-status.sh"),
        "on-click": ($settings[0].services.syncthing.on_click // ($app_open + " xdg-open " + ($settings[0].services.syncthing.gui_url // "https://localhost:8384"))),
        "on-click-right": ($settings[0].services.syncthing.on_click_right // ($app_open + " systemctl --user restart " + ($settings[0].services.syncthing.service_name // $syncthing_service))),
        "on-click-middle": ($scripts + "/services/sync/syncthing-status.sh --refresh")
      },
      "custom/sunshine": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("sunshine"),
        signal: signal("sunshine"),
        exec: ($scripts + "/services/apps/sunshine-status.sh"),
        "on-click": ($settings[0].services.sunshine.on_click // ($app_open + " xdg-open " + ($settings[0].services.sunshine.gui_url // "https://localhost:47990"))),
        "on-click-right": ($settings[0].services.sunshine.on_click_right // ($app_open + " systemctl --user restart " + ($settings[0].services.sunshine.service_name // "app-dev.lizardbyte.app.Sunshine.service"))),
        "on-click-middle": ($scripts + "/services/apps/sunshine-status.sh --refresh")
      }
    }
    '
}

jq '.bars' "$settings" >"$bar_defaults_out"

layout_keys_jq='
  if .modules_center then . + {"modules-center": .modules_center} | del(.modules_center) else . end
  | if .modules_right then . + {"modules-right": .modules_right} | del(.modules_right) else . end
  | if .modules_left then . + {"modules-left": .modules_left} | del(.modules_left) else . end
'

jq ".layouts.top | $layout_keys_jq" "$settings" >"$top_layout_out"

jq ".layouts.bottom | $layout_keys_jq" "$settings" >"$bottom_layout_out"

build_groups_json | jq '.' >"$groups_out"

build_system_json | jq -c '.' >"$system_out"

if [ -x "$WAYBAR_SCRIPTS/generate/generate-network-modules.sh" ]; then
  "$WAYBAR_SCRIPTS/generate/generate-network-modules.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/generate/generate-dock-modules.sh" ]; then
  "$WAYBAR_SCRIPTS/generate/generate-dock-modules.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/generate/generate-module-configs.sh" ]; then
  "$WAYBAR_SCRIPTS/generate/generate-module-configs.sh"
fi
