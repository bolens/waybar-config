#!/usr/bin/env python3
"""Parse KWin WindowsRunner qdbus --literal Match output for dock-windows.

KRunner's Match method returns typed D-Bus literals only (no JSON). Each entry
is `[Argument: (sssida{sv}) "id", "title", "app", …]` with optional a{sv}
props. Field order is id / title / app; screen/output may appear in props.

When screen props are missing (common on Plasma), enrich via
``org.kde.KWin.getWindowInfo`` geometry + kscreen-doctor output rects so
``dock_windows.per_output`` can filter dual-monitor bars.

Hermetic CI fixtures (no live qdbus/kscreen):

* ``WAYBAR_TEST_NO_QDBUS=1`` — skip real qdbus calls
* ``WAYBAR_TEST_OUTPUT_GEOMS='NAME:x,y,WxH;…'`` — fake output rectangles
* ``WAYBAR_TEST_WINDOW_INFO_MAP='uuid=x,y,WxH;…'`` — fake window geometries
  (uuid may be bare or ``{uuid}``; WindowsRunner ids use ``0_{uuid}``)
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from typing import Any

# Entry marker in qdbus6 --literal output for krunner Match results.
_ENTRY_MARK = "[Argument: (sssida{sv}) "

# Optional screen/output props (WindowsRunner / fixture metadata).
_SCREEN_KEY_RE = re.compile(
    r'"(?:screen|output|monitor)"\s*=\s*'
    r'(?:'
    r'\[Variant:\s*\[Argument:\s*s\s*("(?:\\.|[^"\\])*")\]\]'
    r'|'
    r'("(?:\\.|[^"\\])*")'
    r')',
    re.IGNORECASE,
)

_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
_GEOM_RE = re.compile(
    r"Geometry:\s*(-?\d+)\s*,\s*(-?\d+)\s+(\d+)x(\d+)",
    re.IGNORECASE,
)
_OUTPUT_RE = re.compile(r"Output:\s*(?:\d+\s+)?(\S+)", re.IGNORECASE)
_INFO_NUM_RE = re.compile(
    r'"(x|y|width|height)"\s*=\s*\[Variant(?:\([^)]*\))?:\s*([0-9.+-]+)\]',
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


def runner_id_to_uuid(runner_id: str) -> str | None:
    """Map WindowsRunner id ``0_{uuid}`` → ``{uuid}`` for getWindowInfo."""
    rid = (runner_id or "").strip()
    if not rid:
        return None
    if rid.startswith("0_{") and rid.endswith("}"):
        return "{" + rid[3:-1] + "}"
    if rid.startswith("{") and rid.endswith("}"):
        return rid
    # Bare uuid
    if re.fullmatch(r"[0-9a-fA-F-]{36}", rid):
        return "{" + rid + "}"
    return None


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


def parse_output_geometries(text: str) -> list[dict[str, Any]]:
    """Parse kscreen-doctor -o (ANSI-stripped) into name/x/y/w/h dicts."""
    text = _ANSI_RE.sub("", text or "")
    geoms: list[dict[str, Any]] = []
    current: str | None = None
    for line in text.splitlines():
        om = _OUTPUT_RE.search(line)
        if om:
            current = om.group(1)
            continue
        gm = _GEOM_RE.search(line)
        if gm and current:
            geoms.append(
                {
                    "name": current,
                    "x": int(gm.group(1)),
                    "y": int(gm.group(2)),
                    "w": int(gm.group(3)),
                    "h": int(gm.group(4)),
                }
            )
    return geoms


def load_output_geometries() -> list[dict[str, Any]]:
    """Load output rects from env fixture or kscreen-doctor."""
    fixture = os.environ.get("WAYBAR_TEST_OUTPUT_GEOMS", "").strip()
    if fixture:
        # name:x,y,wxh;name2:...
        geoms: list[dict[str, Any]] = []
        for part in fixture.split(";"):
            part = part.strip()
            if not part or ":" not in part:
                continue
            name, rest = part.split(":", 1)
            m = re.fullmatch(r"(-?\d+),(-?\d+),(\d+)x(\d+)", rest.strip())
            if not m:
                continue
            geoms.append(
                {
                    "name": name.strip(),
                    "x": int(m.group(1)),
                    "y": int(m.group(2)),
                    "w": int(m.group(3)),
                    "h": int(m.group(4)),
                }
            )
        return geoms

    if os.environ.get("WAYBAR_TEST_NO_QDBUS") in ("1", "true", "TRUE", "yes", "YES"):
        return []

    try:
        proc = subprocess.run(
            ["kscreen-doctor", "-o"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
            env={**os.environ, "TERM": "dumb", "NO_COLOR": "1"},
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    return parse_output_geometries(proc.stdout or "")


def parse_window_info_geometry(literal: str) -> tuple[float, float] | None:
    """Return window center (cx, cy) from getWindowInfo --literal output."""
    vals: dict[str, float] = {}
    for key, num in _INFO_NUM_RE.findall(literal or ""):
        try:
            vals[key.lower()] = float(num)
        except ValueError:
            continue
    if not all(k in vals for k in ("x", "y", "width", "height")):
        return None
    return (
        vals["x"] + vals["width"] / 2.0,
        vals["y"] + vals["height"] / 2.0,
    )


def output_for_point(
    cx: float, cy: float, geoms: list[dict[str, Any]]
) -> str | None:
    """Pick the output whose rect contains (cx, cy); prefer smallest area on ties."""
    hits: list[tuple[int, str]] = []
    for g in geoms:
        x, y, w, h = g["x"], g["y"], g["w"], g["h"]
        if x <= cx < x + w and y <= cy < y + h:
            hits.append((w * h, g["name"]))
    if not hits:
        return None
    hits.sort(key=lambda t: t[0])
    return hits[0][1]


def parse_window_info_fields(text: str) -> dict[str, str]:
    """Extract resourceClass / resourceName / desktopFile / caption from getWindowInfo."""
    text = text or ""
    out: dict[str, str] = {}
    for key in ("resourceClass", "resourceName", "desktopFile", "caption"):
        m = re.search(
            rf'"{key}"\s*=\s*\[Variant(?:\([^)]*\))?:\s*"((?:\\.|[^"\\])*)"\]',
            text,
        )
        if m:
            out[key] = m.group(1).replace('\\"', '"').replace("\\\\", "\\")
    return out


def fetch_window_info_fields(uuid: str) -> dict[str, str]:
    """Call getWindowInfo; honor WAYBAR_TEST_WINDOW_INFO_MAP for class fixtures.

    Fixture form: ``uuid=resourceClass`` or ``uuid=resourceClass|resourceName|desktopFile``.
    Geometry fixtures (``uuid=x,y,WxH``) are ignored here.
    """
    fixture = os.environ.get("WAYBAR_TEST_WINDOW_INFO_MAP", "").strip()
    if fixture:
        for part in fixture.split(";"):
            part = part.strip()
            if not part or "=" not in part:
                continue
            key, rest = part.split("=", 1)
            key = key.strip()
            if key not in (uuid, uuid.strip("{}")):
                continue
            rest = rest.strip()
            # Geometry fixture for enrich_screens — skip.
            if re.fullmatch(
                r"-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?,\d+(?:\.\d+)?x\d+(?:\.\d+)?",
                rest,
            ):
                return {}
            bits = rest.split("|")
            fields = {
                "resourceClass": bits[0] if bits else "",
                "resourceName": bits[1] if len(bits) > 1 else "",
                "desktopFile": bits[2] if len(bits) > 2 else "",
                "caption": bits[3] if len(bits) > 3 else "",
            }
            return {k: v for k, v in fields.items() if v}

    if os.environ.get("WAYBAR_TEST_NO_QDBUS") in ("1", "true", "TRUE", "yes", "YES"):
        return {}

    try:
        proc = subprocess.run(
            [
                "qdbus6",
                "--literal",
                "org.kde.KWin",
                "/KWin",
                "org.kde.KWin.getWindowInfo",
                uuid,
            ],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    return parse_window_info_fields(proc.stdout or "")


def enrich_resource_meta(
    entries: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Fill resourceClass/resourceName/desktopFile when WindowsRunner app is blank."""
    for e in entries:
        if e.get("resourceClass"):
            continue
        uuid = runner_id_to_uuid(str(e.get("id") or ""))
        if not uuid:
            continue
        fields = fetch_window_info_fields(uuid)
        if not fields:
            continue
        if fields.get("resourceClass"):
            e["resourceClass"] = fields["resourceClass"]
        if fields.get("resourceName"):
            e["resourceName"] = fields["resourceName"]
        if fields.get("desktopFile"):
            e["desktopFile"] = fields["desktopFile"]
        # Prefer real class over empty WindowsRunner app field.
        if not (e.get("app") or "").strip() and fields.get("resourceClass"):
            e["app"] = fields["resourceClass"]
    return entries


def fetch_window_center(uuid: str) -> tuple[float, float] | None:
    """Call getWindowInfo for uuid; honor WAYBAR_TEST_WINDOW_INFO_MAP geometry fixtures."""
    fixture = os.environ.get("WAYBAR_TEST_WINDOW_INFO_MAP", "").strip()
    if fixture:
        # uuid=x,y,wxh;...
        for part in fixture.split(";"):
            part = part.strip()
            if not part or "=" not in part:
                continue
            key, rest = part.split("=", 1)
            key = key.strip()
            if key not in (uuid, uuid.strip("{}")):
                continue
            m = re.fullmatch(
                r"(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?),(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)",
                rest.strip(),
            )
            if not m:
                continue
            x, y, w, h = map(float, m.groups())
            return (x + w / 2.0, y + h / 2.0)
        return None

    if os.environ.get("WAYBAR_TEST_NO_QDBUS") in ("1", "true", "TRUE", "yes", "YES"):
        return None

    try:
        proc = subprocess.run(
            [
                "qdbus6",
                "--literal",
                "org.kde.KWin",
                "/KWin",
                "org.kde.KWin.getWindowInfo",
                uuid,
            ],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return parse_window_info_geometry(proc.stdout or "")


def enrich_screens(
    entries: list[dict[str, Any]],
    *,
    geoms: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Fill missing screen fields via getWindowInfo geometry + output rects."""
    if not entries:
        return entries
    if all(e.get("screen") for e in entries):
        return entries

    if geoms is None:
        geoms = load_output_geometries()
    if not geoms:
        return entries

    for e in entries:
        if e.get("screen"):
            continue
        uuid = runner_id_to_uuid(str(e.get("id") or ""))
        if not uuid:
            continue
        center = fetch_window_center(uuid)
        if not center:
            continue
        name = output_for_point(center[0], center[1], geoms)
        if name:
            e["screen"] = name
    return entries


def filter_by_output(
    entries: list[dict[str, Any]], output: str | None
) -> list[dict[str, Any]]:
    """Filter to output when any entry has screen metadata; else return all.

    When KWin omits screen props, filtering would empty the dock on multi-monitor
    setups — keep every window until metadata is actually present.
    """
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
        if not _keep_window_entry(e):
            continue
        win_id = e.get("id") or ""
        title = e.get("title") or ""
        app = e.get("app") or ""
        if for_click:
            display = title if title else app
            lines.append(f"{win_id}|{display}")
        else:
            lines.append(f"{title}|{app}")
    return lines


# Shell/panel chrome that must never occupy dock-windows slots.
_SKIP_RESOURCE_CLASSES = frozenset(
    {
        "waybar",
        "plasmashell",
        "plasmashellsilent",
        "krunner",
        "kwin",
        "ksmserver-logout-greeter",
        "xwaylandvideobridge",
        "xdg-desktop-portal-kde",
    }
)


def _keep_window_entry(e: dict[str, Any]) -> bool:
    """Drop ghost/chrome windows (empty title + panel classes)."""
    win_id = e.get("id") or ""
    if not win_id:
        return False
    title = (e.get("title") or "").strip()
    app = (e.get("app") or "").strip()
    rc = (e.get("resourceClass") or app or "").strip().lower()
    bare = rc.split(".")[-1] if rc else ""
    if bare in _SKIP_RESOURCE_CLASSES or rc in _SKIP_RESOURCE_CLASSES:
        return False
    if not title and not app:
        return False
    # Empty-title ghosts still pollute slots after resourceClass fill.
    if not title:
        return False
    return True


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
    p_parse.add_argument(
        "--no-enrich",
        action="store_true",
        help="Skip getWindowInfo/kscreen geometry enrichment",
    )

    args = parser.parse_args(argv)
    raw = sys.stdin.read()
    entries = parse_windows_runner_literal(raw)
    if not args.no_enrich:
        # Always fill resourceClass — WindowsRunner app field is often blank.
        entries = enrich_resource_meta(entries)
        # Geometry/kscreen enrichment is only needed for per-output filtering.
        if args.output:
            entries = enrich_screens(entries)
    entries = filter_by_output(entries, args.output or None)

    if args.json:
        import json

        entries = [e for e in entries if _keep_window_entry(e)]
        json.dump(entries, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0

    for_click = args.mode == "click"
    for line in entries_as_lines(entries, for_click=for_click):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
