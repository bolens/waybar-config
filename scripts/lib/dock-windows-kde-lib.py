#!/usr/bin/env python3
"""Parse KWin WindowsRunner qdbus --literal Match output for dock-windows."""

from __future__ import annotations

import argparse
import re
import sys
from typing import Any

# Entry marker in qdbus6 --literal output for krunner Match results.
_ENTRY_MARK = "[Argument: (sssida{sv}) "

# Optional screen/output props (future KWin / fixture metadata).
_SCREEN_KEY_RE = re.compile(
    r'"(?:screen|output|monitor)"\s*=\s*'
    r'(?:'
    r'\[Variant:\s*\[Argument:\s*s\s*("(?:\\.|[^"\\])*")\]\]'
    r'|'
    r'("(?:\\.|[^"\\])*")'
    r')',
    re.IGNORECASE,
)


def _parse_quoted(s: str, start: int) -> tuple[str, int] | None:
    """Parse a double-quoted C-ish string starting at s[start]. Return (value, next_idx)."""
    if start >= len(s) or s[start] != '"':
        return None
    i = start + 1
    out: list[str] = []
    while i < len(s):
        ch = s[i]
        if ch == "\\":
            if i + 1 >= len(s):
                out.append("\\")
                i += 1
                break
            nxt = s[i + 1]
            # qdbus may emit \' for apostrophe; treat as the following char.
            out.append(nxt)
            i += 2
            continue
        if ch == '"':
            return "".join(out), i + 1
        out.append(ch)
        i += 1
    return None


def _skip_ws(s: str, i: int) -> int:
    while i < len(s) and s[i] in " \t\r\n":
        i += 1
    return i


def _extract_screen(props_blob: str) -> str | None:
    m = _SCREEN_KEY_RE.search(props_blob)
    if not m:
        return None
    raw = m.group(1) or m.group(2)
    if not raw:
        return None
    parsed = _parse_quoted(raw, 0)
    return parsed[0] if parsed else raw.strip('"')


def parse_windows_runner_literal(raw: str) -> list[dict[str, Any]]:
    """
    Resiliently parse qdbus --literal org.kde.krunner1.Match output.

    Returns list of dicts: id, title, app, screen (screen may be None).
    """
    if not raw or not raw.strip():
        return []

    entries: list[dict[str, Any]] = []
    pos = 0
    while True:
        idx = raw.find(_ENTRY_MARK, pos)
        if idx < 0:
            break
        i = idx + len(_ENTRY_MARK)
        fields: list[str] = []
        ok = True
        for _ in range(3):
            i = _skip_ws(raw, i)
            parsed = _parse_quoted(raw, i)
            if not parsed:
                ok = False
                break
            val, i = parsed
            fields.append(val)
            i = _skip_ws(raw, i)
            if i < len(raw) and raw[i] == ",":
                i += 1
        if not ok or len(fields) < 3:
            pos = idx + len(_ENTRY_MARK)
            continue

        # Remainder of this entry until the next entry mark.
        next_mark = raw.find(_ENTRY_MARK, i)
        end = next_mark if next_mark >= 0 else len(raw)
        props_start = raw.find("[Argument: a{sv}", i, end)
        props_blob = raw[props_start:end] if props_start >= 0 else ""

        win_id, title, app = fields[0], fields[1], fields[2]
        screen = _extract_screen(props_blob) if props_blob else None
        entries.append(
            {
                "id": win_id,
                "title": title,
                "app": app,
                "screen": screen,
            }
        )
        pos = next_mark if next_mark >= 0 else end

    return entries


def filter_by_output(
    entries: list[dict[str, Any]], output: str | None
) -> list[dict[str, Any]]:
    """Filter to output when any entry has screen metadata; else return all."""
    if not output:
        return entries
    if not any(e.get("screen") for e in entries):
        return entries
    return [e for e in entries if (e.get("screen") or "") == output]


def entries_as_lines(
    entries: list[dict[str, Any]], *, for_click: bool = False
) -> list[str]:
    """Emit id|title|app lines (click uses id|title; status uses title|app)."""
    lines: list[str] = []
    for e in entries:
        win_id = e.get("id") or ""
        title = e.get("title") or ""
        app = e.get("app") or ""
        if not win_id:
            continue
        if not title and not app:
            continue
        if for_click:
            display = title if title else app
            lines.append(f"{win_id}|{display}")
        else:
            lines.append(f"{title}|{app}")
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_parse = sub.add_parser("parse", help="Parse literal from stdin → lines")
    p_parse.add_argument("--output", default="", help="Optional WAYBAR_OUTPUT_NAME")
    p_parse.add_argument(
        "--mode",
        choices=("status", "click"),
        default="status",
        help="status → title|app; click → id|title",
    )
    p_parse.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON array instead of pipe lines",
    )

    args = parser.parse_args(argv)
    raw = sys.stdin.read()
    entries = parse_windows_runner_literal(raw)
    entries = filter_by_output(entries, args.output or None)

    if args.json:
        import json

        json.dump(entries, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0

    for_click = args.mode == "click"
    for line in entries_as_lines(entries, for_click=for_click):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
