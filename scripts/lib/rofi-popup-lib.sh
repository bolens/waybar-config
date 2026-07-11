#!/usr/bin/env bash
# Shared Rofi popup row / text formatters (wifi / bluetooth / calendar / similar menus).

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
