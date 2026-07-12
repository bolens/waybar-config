#!/usr/bin/env sh
# Unicode block gauge helpers for Waybar status text.

# gauge_bar PCT [WIDTH]
# PCT: 0–100 integer (clamped). WIDTH: bar length, default 8 (empty → 8).
# Maps fill to ▁▂▃▄▅▆▇█.
gauge_bar() {
  _pct="${1:-0}"
  _width="${2:-8}"
  [ -z "$_width" ] && _width=8

  case "$_pct" in
    '' | *[!0-9-]*) _pct=0 ;;
  esac
  case "$_width" in
    '' | *[!0-9]*) _width=8 ;;
  esac
  [ "$_width" -lt 1 ] && _width=8

  if [ "$_pct" -lt 0 ]; then
    _pct=0
  elif [ "$_pct" -gt 100 ]; then
    _pct=100
  fi

  _out=""
  _i=0
  while [ "$_i" -lt "$_width" ]; do
    # Units filled across the whole bar (0 .. width*8).
    _filled=$((_pct * _width * 8 / 100))
    _cell_start=$((_i * 8))
    _cell_units=$((_filled - _cell_start))
    if [ "$_cell_units" -le 0 ]; then
      _level=0
    elif [ "$_cell_units" -ge 8 ]; then
      _level=7
    else
      _level=$((_cell_units - 1))
      [ "$_level" -lt 0 ] && _level=0
    fi
    case "$_level" in
      0) _ch='▁' ;;
      1) _ch='▂' ;;
      2) _ch='▃' ;;
      3) _ch='▄' ;;
      4) _ch='▅' ;;
      5) _ch='▆' ;;
      6) _ch='▇' ;;
      *) _ch='█' ;;
    esac
    _out="${_out}${_ch}"
    _i=$((_i + 1))
  done
  printf '%s' "$_out"
}
