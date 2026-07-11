"""Locale-aware temperature formatting (Python twin of waybar-locale-lib.sh)."""

from __future__ import annotations


def format_locale_temp(temp_c: float, unit: str = "C", mode: str = "both") -> str:
    """Format Celsius as short/both strings using preferred unit C or F."""
    c = int(round(float(temp_c)))
    f = c * 9 // 5 + 32
    prefer_f = (unit or "C").strip().upper() == "F"
    if mode == "short":
        return f"{f}°F" if prefer_f else f"{c}°C"
    if prefer_f:
        return f"{f}°F ({c}°C)"
    return f"{c}°C ({f}°F)"
