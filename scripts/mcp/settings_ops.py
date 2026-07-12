"""Settings read/patch/diff/backup helpers."""

from __future__ import annotations

import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonc_util import (
    deep_merge,
    dump_json,
    get_path,
    load_jsonc,
    path_looks_secret,
    redact_secrets,
    search_tree,
    set_path,
    unset_path,
)
from paths import SETTINGS_SCHEMA, WaybarPaths


def load_settings(paths: WaybarPaths, *, include_secrets: bool = False) -> dict[str, Any]:
    if not paths.settings_jsonc.is_file():
        raise FileNotFoundError(f"missing settings: {paths.settings_jsonc}")
    data = load_jsonc(str(paths.settings_jsonc))
    if not isinstance(data, dict):
        raise ValueError("settings root must be a JSON object")
    if include_secrets and paths.secrets_jsonc.is_file():
        secrets = load_jsonc(str(paths.secrets_jsonc))
        if isinstance(secrets, dict):
            data = deep_merge(data, secrets)
    return data


def get_settings(
    paths: WaybarPaths,
    path: str | None = None,
    *,
    include_secrets: bool = False,
) -> Any:
    data = load_settings(paths, include_secrets=include_secrets)
    if path:
        data = get_path(data, path)
    return redact_secrets(data)


def write_settings(paths: WaybarPaths, data: dict[str, Any]) -> None:
    paths.settings_jsonc.parent.mkdir(parents=True, exist_ok=True)
    dump_json(data, str(paths.settings_jsonc))
    # Keep compiled .json in sync for shell helpers.
    dump_json(data, str(paths.settings_json))


def patch_settings(
    paths: WaybarPaths,
    overlay: dict[str, Any],
    *,
    dry_run: bool = False,
) -> dict[str, Any]:
    _refuse_secret_overlay(overlay)
    before = load_settings(paths)
    after = deep_merge(before, overlay)
    if not dry_run:
        write_settings(paths, after)
    return {"dry_run": dry_run, "before": before, "after": after}


def diff_settings(paths: WaybarPaths, overlay: dict[str, Any]) -> dict[str, Any]:
    return patch_settings(paths, overlay, dry_run=True)


def set_settings_path(
    paths: WaybarPaths, path: str, value: Any, *, dry_run: bool = False
) -> dict[str, Any]:
    if path_looks_secret(path):
        raise ValueError(f"refusing to write secret-looking path: {path}")
    before = load_settings(paths)
    after = set_path(before, path, value)
    if not dry_run:
        write_settings(paths, after)
    return {"dry_run": dry_run, "path": path, "value": value, "written": not dry_run}


def unset_settings_path(
    paths: WaybarPaths, path: str, *, dry_run: bool = False
) -> dict[str, Any]:
    if path_looks_secret(path):
        raise ValueError(f"refusing to unset secret-looking path: {path}")
    before = load_settings(paths)
    after = unset_path(before, path)
    if not dry_run:
        write_settings(paths, after)
    return {"dry_run": dry_run, "path": path, "written": not dry_run}


def overview(paths: WaybarPaths) -> dict[str, Any]:
    data = load_settings(paths)
    theme = data.get("theme") if isinstance(data.get("theme"), dict) else {}
    bars = data.get("bars") if isinstance(data.get("bars"), dict) else {}
    layouts = data.get("layouts") if isinstance(data.get("layouts"), dict) else {}
    groups = data.get("groups") if isinstance(data.get("groups"), dict) else {}
    visual = data.get("visual") if isinstance(data.get("visual"), dict) else {}
    dock_windows = (
        data.get("dock_windows") if isinstance(data.get("dock_windows"), dict) else {}
    )
    cava = data.get("cava") if isinstance(data.get("cava"), dict) else {}
    profiles = []
    if paths.profiles_dir.is_dir():
        profiles = sorted(p.stem for p in paths.profiles_dir.glob("*.jsonc"))
    return {
        "waybar_home": str(paths.home),
        "theme": {
            "mode": theme.get("mode"),
            "preset": theme.get("preset"),
        },
        "bars": {
            "layer": bars.get("layer"),
            "floating": bars.get("floating"),
            "height": bars.get("height"),
        },
        "layouts": {
            name: {
                "position": block.get("position") if isinstance(block, dict) else None,
                "modules_left": (block.get("modules_left") if isinstance(block, dict) else None),
                "modules_center": (
                    block.get("modules_center") if isinstance(block, dict) else None
                ),
                "modules_right": (
                    block.get("modules_right") if isinstance(block, dict) else None
                ),
            }
            for name, block in layouts.items()
        },
        "groups": sorted(groups.keys()),
        "features": {
            "dock_windows": dock_windows.get("enabled"),
            "cava_placement": cava.get("placement"),
            "visual_gauges": (visual.get("gauges") or {}).get("enabled")
            if isinstance(visual.get("gauges"), dict)
            else None,
            "album_art": (visual.get("album_art") or {}).get("enabled")
            if isinstance(visual.get("album_art"), dict)
            else None,
            "stats_carousel": (visual.get("stats_carousel") or {}).get("enabled")
            if isinstance(visual.get("stats_carousel"), dict)
            else None,
        },
        "secrets_present": paths.secrets_jsonc.is_file(),
        "profiles": profiles,
    }


def describe(paths: WaybarPaths) -> str:
    return f"""Waybar config MCP playbook

WAYBAR_HOME: {paths.home}
Source of truth: {paths.settings_jsonc}
Compiled JSON: {paths.settings_json}
Themes: {paths.themes_dir}
Profiles: {paths.profiles_dir}
Secrets (gitignored, never commit): {paths.secrets_jsonc}
Secrets example: {paths.secrets_example}

Workflow:
1. waybar_backup_settings (optional but recommended)
2. Edit via waybar_patch_settings / waybar_set_path / theme/layout/group tools
3. waybar_generate
4. waybar_validate
5. waybar_restart with confirm=true (reloads user systemd unit)

Rules:
- Do NOT hand-edit *.generated.jsonc / *.generated.css
- Programmatic settings writes rewrite pretty JSON (comments in .jsonc are lost)
- Never write live secrets via MCP; use secrets scripts / example template
- Prefer profiles (e.g. minimal-groups) for bulk group overrides
"""


def schema() -> dict[str, str]:
    return dict(SETTINGS_SCHEMA)


def search_settings(
    paths: WaybarPaths, query: str, *, limit: int = 50
) -> list[dict[str, Any]]:
    data = load_settings(paths)
    return search_tree(data, query, limit=limit)


def backup_settings(paths: WaybarPaths) -> dict[str, Any]:
    if not paths.settings_jsonc.is_file():
        raise FileNotFoundError(f"missing settings: {paths.settings_jsonc}")
    paths.backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest = paths.backup_dir / f"waybar-settings.jsonc.bak.{stamp}"
    shutil.copy2(paths.settings_jsonc, dest)
    # Also keep a sibling copy under data/ for discoverability.
    sibling = paths.data_dir / f"waybar-settings.jsonc.bak.{stamp}"
    shutil.copy2(paths.settings_jsonc, sibling)
    return {"backup": str(dest), "sibling": str(sibling)}


def list_backups(paths: WaybarPaths) -> list[str]:
    found: list[Path] = []
    if paths.backup_dir.is_dir():
        found.extend(paths.backup_dir.glob("waybar-settings.jsonc.bak.*"))
    found.extend(paths.data_dir.glob("waybar-settings.jsonc.bak.*"))
    return sorted({str(p.resolve()) for p in found})


def restore_settings(paths: WaybarPaths, backup_path: str) -> dict[str, Any]:
    src = Path(backup_path).expanduser().resolve()
    allowed = [paths.backup_dir, paths.data_dir]
    paths.safe_under(src, *allowed)
    if not src.is_file():
        raise FileNotFoundError(f"backup not found: {src}")
    if "waybar-settings.jsonc.bak." not in src.name:
        raise ValueError("backup filename must look like waybar-settings.jsonc.bak.<stamp>")
    shutil.copy2(src, paths.settings_jsonc)
    data = load_jsonc(str(paths.settings_jsonc))
    if isinstance(data, dict):
        dump_json(data, str(paths.settings_json))
    return {"restored_from": str(src), "settings": str(paths.settings_jsonc)}


def _refuse_secret_overlay(overlay: Any, prefix: str = "") -> None:
    if isinstance(overlay, dict):
        for key, value in overlay.items():
            path = f"{prefix}.{key}" if prefix else key
            if path_looks_secret(path) or path_looks_secret(key):
                raise ValueError(
                    f"refusing overlay key that looks like a secret: {path}"
                )
            _refuse_secret_overlay(value, path)
