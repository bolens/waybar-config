"""Generated modules and scripts catalog."""

from __future__ import annotations

import json
from typing import Any

from jsonc_util import load_jsonc
from paths import WaybarPaths


SCRIPT_DOMAINS = (
    "lib",
    "generate",
    "ci",
    "infra",
    "listeners",
    "dock",
    "workspaces",
    "system",
    "network",
    "media",
    "notifications",
    "capture",
    "services",
    "tools",
    "mcp",
)


def list_modules(paths: WaybarPaths) -> dict[str, Any]:
    ids: set[str] = set()
    sources: dict[str, str] = {}
    include = paths.includes_dir / "modules.jsonc"
    if include.is_file():
        try:
            data = load_jsonc(str(include))
            if isinstance(data, dict):
                for key in data:
                    ids.add(key)
                    sources[key] = str(include)
        except (OSError, json.JSONDecodeError, ValueError):
            pass
    if paths.modules_dir.is_dir():
        for path in sorted(paths.modules_dir.glob("*.generated.jsonc")):
            try:
                data = load_jsonc(str(path))
            except (OSError, json.JSONDecodeError, ValueError):
                continue
            if isinstance(data, dict):
                for key in data:
                    ids.add(key)
                    sources.setdefault(key, str(path))
    return {"modules": sorted(ids), "sources": sources}


def get_module(paths: WaybarPaths, module_id: str) -> dict[str, Any]:
    catalog = list_modules(paths)
    if module_id not in catalog["modules"]:
        # Search generated files even if include index missing.
        pass
    if paths.modules_dir.is_dir():
        for path in sorted(paths.modules_dir.glob("*.generated.jsonc")):
            try:
                data = load_jsonc(str(path))
            except (OSError, json.JSONDecodeError, ValueError):
                continue
            if isinstance(data, dict) and module_id in data:
                return {
                    "id": module_id,
                    "file": str(path),
                    "config": data[module_id],
                }
    include = paths.includes_dir / "modules.jsonc"
    if include.is_file():
        data = load_jsonc(str(include))
        if isinstance(data, dict) and module_id in data:
            return {
                "id": module_id,
                "file": str(include),
                "config": data[module_id],
            }
    raise KeyError(f"module not found: {module_id}")


def list_generated(paths: WaybarPaths) -> list[str]:
    found: list[str] = []
    for root_name in ("modules", "layouts", "includes", "theme"):
        root = paths.home / root_name
        if not root.is_dir():
            continue
        for pattern in ("*.generated.jsonc", "*.generated.css"):
            found.extend(str(p.relative_to(paths.home)) for p in root.rglob(pattern))
    return sorted(found)


def read_generated(paths: WaybarPaths, rel_path: str) -> str:
    if ".." in rel_path or rel_path.startswith("/"):
        raise ValueError("invalid generated path")
    if ".generated." not in rel_path:
        raise ValueError("path must be a *.generated.* artifact")
    path = (paths.home / rel_path).resolve()
    paths.safe_under(
        path,
        paths.modules_dir,
        paths.layouts_dir,
        paths.includes_dir,
        paths.theme_dir,
    )
    if not path.is_file():
        raise FileNotFoundError(f"generated file not found: {rel_path}")
    return path.read_text(encoding="utf-8")


def list_scripts(paths: WaybarPaths) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for domain in SCRIPT_DOMAINS:
        d = paths.scripts_dir / domain
        if not d.is_dir():
            out[domain] = []
            continue
        files = []
        for p in sorted(d.rglob("*")):
            if p.is_file() and p.suffix in {".sh", ".py"}:
                files.append(str(p.relative_to(paths.scripts_dir)))
        out[domain] = files
    return out


def find_script(paths: WaybarPaths, query: str) -> list[str]:
    q = query.lower().removeprefix("custom/").replace("_", "-")
    hits: list[str] = []
    if not paths.scripts_dir.is_dir():
        return hits
    for p in paths.scripts_dir.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix not in {".sh", ".py"}:
            continue
        name = p.name.lower()
        stem = p.stem.lower()
        if q in name or q in stem or q.replace("-", "") in stem.replace("-", ""):
            hits.append(str(p.relative_to(paths.scripts_dir)))
    return sorted(hits)[:50]
