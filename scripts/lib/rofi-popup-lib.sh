#!/usr/bin/env bash
# Shared Rofi popup row / text formatters (wifi / bluetooth / calendar / similar menus).

# Print a -theme-str snippet using theme.colors from settings.
# Requires waybar-settings.sh already sourced.
# Optional env overrides: ROFI_THEME_WIDTH, ROFI_THEME_LINES, ROFI_THEME_COLUMNS,
# ROFI_THEME_RADIUS, ROFI_THEME_PADDING, ROFI_THEME_ELEMENT_PAD, ROFI_THEME_ORIENTATION,
# ROFI_THEME_FONT_SIZE, ROFI_THEME_BORDER (critical|accent).
rofi_theme_str_from_settings() {
  local critical accent foreground background tooltip_bg
  local width lines columns radius padding element_pad orientation font_size border_mode
  local border_color selected_bg text_color entry_bg orient_line

  critical="$(waybar_settings_get '.theme.colors.critical' '#ff2a7f')"
  accent="$(waybar_settings_get '.theme.colors.accent' '#00e5ff')"
  # Prefer solid cyan brand when accent is a translucent workspace pill.
  local ws_visible
  ws_visible="$(waybar_settings_get '.theme.colors.workspace_visible' '')"
  if [[ "$accent" == rgba* ]] && [[ -n "$ws_visible" && "$ws_visible" != "null" ]]; then
    accent="$ws_visible"
  fi
  foreground="$(waybar_settings_get '.theme.colors.foreground' '#c8f6ff')"
  background="$(waybar_settings_get '.theme.colors.background' 'rgba(6, 7, 14, 0.92)')"
  tooltip_bg="$(waybar_settings_get '.theme.colors.tooltip_background' '#06070e')"

  # Rofi wants #AARRGGBB or #RRGGBB; soften translucent rgba backgrounds.
  case "$background" in
    rgba*) background="#090b12f2" ;;
  esac

  width="${ROFI_THEME_WIDTH:-380}"
  lines="${ROFI_THEME_LINES:-2}"
  columns="${ROFI_THEME_COLUMNS:-1}"
  radius="${ROFI_THEME_RADIUS:-8}"
  padding="${ROFI_THEME_PADDING:-15}"
  element_pad="${ROFI_THEME_ELEMENT_PAD:-8px 12px}"
  orientation="${ROFI_THEME_ORIENTATION:-}"
  font_size="${ROFI_THEME_FONT_SIZE:-12}"
  border_mode="${ROFI_THEME_BORDER:-critical}"

  if [[ "$border_mode" == "accent" ]]; then
    border_color="$accent"
  else
    border_color="$critical"
  fi
  selected_bg="$critical"
  text_color="$foreground"
  entry_bg="$tooltip_bg"
  orient_line=""
  if [[ -n "$orientation" ]]; then
    orient_line="  orientation: ${orientation};"
  fi

  cat <<EOF
window {
  width: ${width}px;
  location: center;
  anchor: center;
  border: 2px;
  border-color: ${border_color};
  border-radius: ${radius}px;
  background-color: ${background};
  padding: ${padding}px;
}
mainbox {
  spacing: 12px;
  children: [ message, listview ];
  background-color: transparent;
}
message {
  padding: 5px;
  background-color: transparent;
  text-color: ${text_color};
}
listview {
  lines: ${lines};
  columns: ${columns};
  fixed-height: true;
  background-color: transparent;
}
element {
  padding: ${element_pad};
  border-radius: 4px;
  background-color: ${entry_bg};
  text-color: ${text_color};
${orient_line}
}
element selected {
  background-color: ${selected_bg};
  text-color: #ffffff;
}
element-text {
  font: "JetBrainsMono Nerd Font ${font_size}";
  background-color: transparent;
  text-color: inherit;
  horizontal-align: 0.5;
}
EOF
}

format_header_row() {
  label="$1"
  value="$2"
  width="${3:-52}"
  awk -v l="$label" -v v="$value" -v w="$width" 'BEGIN {
    pad = w - length(l) - length(v)
    if (pad < 1) pad = 1
    printf "%s%*s%s", l, pad, "", v
  }'
}

format_hints_row() {
  hint1="$1"
  hint2="$2"
  width="${3:-52}"
  awk -v h1="$hint1" -v h2="$hint2" -v w="$width" 'BEGIN {
    pad = w - length(h1) - length(h2)
    if (pad < 1) pad = 1
    printf "%s%*s%s", h1, pad, "", h2
  }'
}

# Center text within a fixed width (calendar month grids, etc.).
center_text() {
  text="$1"
  width="${2:-38}"
  awk -v text="$text" -v width="$width" 'BEGIN {
    pad = int((width - length(text)) / 2)
    if (pad < 0) pad = 0
    printf "%*s%s", pad, "", text
  }'
}
