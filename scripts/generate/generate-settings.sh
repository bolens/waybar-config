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

network_interface_modules() {
  if [[ ! -f "$network_manifest" ]]; then
    return 0
  fi
  jq -r '.interfaces[]?.id // empty' "$network_manifest" | while read -r id; do
    [[ -n "$id" ]] && printf 'custom/%s\n' "$id"
  done
}

build_groups_json() {
  # Media / hardware module lists are post-processed from settings:
  # - cava.placement=inline → move custom/cava to the front so it stays visible as the
  #   drawer head (always shown); remaining modules are drawer children. Prefer cava.bars
  #   12–16 when using inline. placement=drawer keeps settings order (handle then cava…).
  # - visual.album_art.enabled → insert custom/album-art before custom/mpris (or mpris).
  # - visual.stats_carousel.enabled → replace custom/{cpu,memory,disk,gpu} with one
  #   custom/stats-carousel entry in group/hardware.
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
      # Expand @network.interfaces → custom/<id> list from network-interfaces.json.
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

    # --- media transforms (keep in sync with generate-drawers-modules.sh for tooltip labels) ---
    def insert_album_art($mods):
      # visual.album_art.enabled → insert custom/album-art immediately before mpris.
      if (($settings[0].visual.album_art.enabled // false) == true) then
        if (($mods | index("custom/album-art")) != null) then $mods
        else
          ($mods | index("custom/mpris")) as $i
          | if $i != null then
              ($mods[:$i] + ["custom/album-art"] + $mods[$i:])
            else
              ($mods | index("mpris")) as $j
              | if $j != null then
                  ($mods[:$j] + ["custom/album-art"] + $mods[$j:])
                else
                  $mods + ["custom/album-art"]
                end
            end
        end
      else
        $mods
      end;

    def apply_cava_placement($mods):
      # cava.enabled=false → strip; placement=inline → cava first (always-visible head).
      # Note: jq `//` treats false as missing — use == false, not `enabled // true`.
      (($settings[0].cava.enabled == false) | not) as $on
      | (($settings[0].cava.placement // "drawer") | tostring) as $place
      | if ($mods | index("custom/cava")) == null then $mods
        elif ($on | not) then
          ($mods | map(select(. != "custom/cava")))
        elif $place == "inline" then
          # Always-visible head: cava first; media-drawer + controls reveal as children.
          (["custom/cava"] + ($mods | map(select(. != "custom/cava"))))
        else
          $mods
        end;

    # --- hardware transforms ---
    def apply_stats_carousel($mods):
      # Replace cpu/memory/disk/gpu entries with one custom/stats-carousel at first hw slot.
      # Keep drawer + other telemetry (nvme/psu/fans/…). Bind . as $m before piping to
      # index — `$hw | index(.)` would rebind . to $hw and match every module.
      if (($settings[0].visual.stats_carousel.enabled // false) != true) then $mods
      else
        ["custom/cpu", "custom/memory", "custom/disk", "custom/gpu"] as $hw
        | ($mods | map(select(. as $m | $hw | index($m) != null)) | length) as $n
        | if $n == 0 then $mods
          else
            ($mods | to_entries | map(select(.value as $v | $hw | index($v) != null)) | .[0].key // 0) as $at
            | ($mods[:$at] | map(select(. as $m | $hw | index($m) == null)))
              + ["custom/stats-carousel"]
              + ($mods[$at:] | map(select(. as $m | $hw | index($m) == null)))
          end
      end;

    def transform_modules($key; $mods):
      if $key == "media" then
        apply_cava_placement(insert_album_art($mods))
      elif $key == "hardware" then
        apply_stats_carousel($mods)
      else
        $mods
      end;

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
            + { modules: transform_modules($key; expand_modules(.value.modules // [])) }
          )
        }
    ) | from_entries
    '
}

build_system_json() {
  local app_open="${scripts}/tools/app-open.sh"

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
    --arg libredefender_service "$libredefender_service" \
    --arg chkrootkit_service "$chkrootkit_service" \
    --arg syncthing_service "$syncthing_service" \
    --arg terminal_app "$terminal_app" \
    '
    def app($key): $settings[0].apps[$key] // "";
    def interval($key): ($settings[0].module_intervals[$key] // $settings[0].poll_intervals[$key] // 1);
    def signal($key): $settings[0].signals[$key] // null;
    def click_app($key): ($scripts + "/tools/app-open-key.sh " + $key);
    def term_cmd($cmd): ($app_open + " " + $terminal_app + " -e " + $cmd);
    # Middle-click: refresh cache then signal by key — Waybar ignores on-click stdout.
    def sig_refresh($key; $script):
      ($script + " --refresh && " + $scripts + "/lib/waybar-signal.sh " + $key);
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
      "custom/stats-carousel": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("stats_carousel"),
        signal: signal("stats_carousel"),
        exec: ($scripts + "/system/stats-carousel-status.sh"),
        "on-click": click_app("system_monitor"),
        "on-click-right": click_app("btop"),
        "on-click-middle": ($scripts + "/system/stats-carousel-status.sh --refresh"),
        "on-scroll-up": ($scripts + "/system/stats-carousel-status.sh --prev"),
        "on-scroll-down": ($scripts + "/system/stats-carousel-status.sh --next")
      },
      "custom/nvme": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("nvme"),
        exec: ($scripts + "/system/nvme-status.sh"),
        "on-click": click_app("btop"),
        "on-click-right": click_app("system_monitor"),
        "on-click-middle": ($scripts + "/system/nvme-status.sh --refresh")
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
        "on-click": ($scripts + "/system/cooling-click.sh open nvtop"),
        "on-click-right": ($scripts + "/system/cooling-click.sh menu btop"),
        "on-click-middle": ($scripts + "/system/fans-status.sh --refresh")
      },
      "custom/liquidctl": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("liquidctl"),
        exec: ($scripts + "/system/liquidctl-status.sh"),
        "on-click": ($scripts + "/system/cooling-click.sh open btop"),
        "on-click-right": ($scripts + "/system/cooling-click.sh menu system_monitor"),
        "on-click-middle": ($scripts + "/system/liquidctl-status.sh --refresh")
      },
      "custom/coolercontrol": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("coolercontrol"),
        signal: signal("coolercontrol"),
        exec: ($scripts + "/services/coolercontrol/coolercontrol-status.sh"),
        "on-click": ($settings[0].services.coolercontrol.on_click // ($app_open + " xdg-open " + ($settings[0].services.coolercontrol.ui_url // "http://127.0.0.1:11987"))),
        "on-click-right": ($settings[0].services.coolercontrol.on_click_right // ($scripts + "/services/coolercontrol/coolercontrol-click.sh menu")),
        "on-click-middle": ($settings[0].services.coolercontrol.on_click_middle // sig_refresh("coolercontrol"; $scripts + "/services/coolercontrol/coolercontrol-status.sh")),
        "on-scroll-up": ($settings[0].services.coolercontrol.on_scroll_up // ($scripts + "/services/coolercontrol/coolercontrol-click.sh next")),
        "on-scroll-down": ($settings[0].services.coolercontrol.on_scroll_down // ($scripts + "/services/coolercontrol/coolercontrol-click.sh prev"))
      },
      "custom/openlinkhub": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("openlinkhub"),
        signal: signal("openlinkhub"),
        exec: ($scripts + "/services/openlinkhub/openlinkhub-status.sh"),
        "on-click": ($settings[0].services.openlinkhub.on_click // ($app_open + " xdg-open " + ($settings[0].services.openlinkhub.ui_url // "http://127.0.0.1:27003"))),
        "on-click-right": ($settings[0].services.openlinkhub.on_click_right // ($app_open + " systemctl restart " + ($settings[0].services.openlinkhub.service_name // "openlinkhub.service"))),
        "on-click-middle": sig_refresh("openlinkhub"; $scripts + "/services/openlinkhub/openlinkhub-status.sh")
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
      "custom/homelab": {
        format: "{}",
        "return-type": "json",
        tooltip: true,
        interval: interval("homelab"),
        signal: signal("homelab"),
        exec: ($scripts + "/services/homelab/homelab-status.sh"),
        "on-click": (
          ($settings[0].homelab.on_click)
          // (
            (($settings[0].homelab.targets // []) | length) as $n
            | if $n == 0 then
                ($scripts + "/services/homelab/homelab-status.sh --refresh")
              elif $n == 1 then
                ($scripts + "/services/homelab/homelab-click.sh open-first")
              else
                ($scripts + "/services/homelab/homelab-click.sh menu")
              end
          )
        ),
        "on-click-right": (
          ($settings[0].homelab.on_click_right)
          // (
            if (($settings[0].homelab.targets // []) | length) > 0 then
              ($scripts + "/services/homelab/homelab-click.sh open-first")
            else
              ($scripts + "/services/homelab/homelab-status.sh --refresh")
            end
          )
        ),
        "on-click-middle": sig_refresh("homelab"; $scripts + "/services/homelab/homelab-status.sh")
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

jq '
  .bars as $b
  | ($b.floating == true) as $float
  | ($b
    | if $float then
        .exclusive = false
        | .["margin-top"] = (.margin_top // 8)
        | .["margin-right"] = (.margin_right // 12)
        | .["margin-bottom"] = (.margin_bottom // 0)
        | .["margin-left"] = (.margin_left // 12)
      else
        .exclusive = (.exclusive // true)
      end
    | del(.floating, .margin_top, .margin_right, .margin_bottom, .margin_left, .glass_opacity, .chrome_radius)
  )
' "$settings" >"$bar_defaults_out"

layout_keys_jq='
  if .modules_center then . + {"modules-center": .modules_center} | del(.modules_center) else . end
  | if .modules_right then . + {"modules-right": .modules_right} | del(.modules_right) else . end
  | if .modules_left then . + {"modules-left": .modules_left} | del(.modules_left) else . end
'

jq ".layouts.top | $layout_keys_jq" "$settings" >"$top_layout_out"

jq "
  . as \$root
  | \$root.layouts.bottom
  | if (\$root.dock_windows.enabled == true) then
      .modules_center = (
        (.modules_center // []) as \$c
        | if (\$c | index(\"group/dock-windows\")) then \$c
          elif (\$c | index(\"custom/dock-windows\")) then
            [\$c[] | if . == \"custom/dock-windows\" then \"group/dock-windows\" else . end]
          else \$c + [\"group/dock-windows\"] end
      )
    else .
    end
  | $layout_keys_jq
" "$settings" >"$bottom_layout_out"

build_groups_json | jq '.' >"$groups_out"

build_system_json | jq -c '.' >"$system_out"

if [ -x "$WAYBAR_SCRIPTS/generate/generate-network-modules.sh" ]; then
  "$WAYBAR_SCRIPTS/generate/generate-network-modules.sh"
fi

if [ -x "$WAYBAR_SCRIPTS/generate/generate-dock-modules.sh" ]; then
  "$WAYBAR_SCRIPTS/generate/generate-dock-modules.sh"
fi

for _gen in \
  generate-utilities-modules.sh \
  generate-audio-modules.sh \
  generate-clock-modules.sh \
  generate-drawers-modules.sh \
  generate-drawers-css.sh \
  generate-groups-css.sh \
  generate-network-custom-modules.sh \
  generate-privacy-modules.sh \
  generate-active-window-modules.sh \
  generate-center-extras-modules.sh \
  generate-dock-windows-modules.sh \
  generate-dock-windows-css.sh \
  generate-dock-appicon-css.sh \
  generate-tray-modules.sh \
  generate-hypr-tools-modules.sh \
  generate-theme-tokens.sh \
  generate-animations-css.sh \
  generate-reduced-motion-css.sh \
  generate-submap-css.sh; do
  if [ -x "$WAYBAR_SCRIPTS/generate/$_gen" ]; then
    "$WAYBAR_SCRIPTS/generate/$_gen"
  elif [ -f "$WAYBAR_SCRIPTS/generate/$_gen" ]; then
    bash "$WAYBAR_SCRIPTS/generate/$_gen"
  fi
done
