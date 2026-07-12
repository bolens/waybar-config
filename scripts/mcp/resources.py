"""MCP resources/list and resources/read."""

from __future__ import annotations

import json
from typing import Any

import manifest_ops
import settings_ops
import theme_ops
from paths import MANIFEST_FILES, WaybarPaths
from protocol import error_result


def list_resources(paths: WaybarPaths) -> list[dict[str, Any]]:
    resources = [
        {
            "uri": "waybar://overview",
            "name": "Waybar overview",
            "description": "Compact config overview JSON",
            "mimeType": "application/json",
        },
        {
            "uri": "waybar://settings",
            "name": "Settings (no secrets)",
            "description": "Stripped settings JSON without secrets overlay",
            "mimeType": "application/json",
        },
        {
            "uri": "waybar://settings-raw",
            "name": "Settings SoT path",
            "description": "Pointer to waybar-settings.jsonc",
            "mimeType": "application/json",
        },
        {
            "uri": "waybar://themes",
            "name": "Theme index",
            "description": "Available theme presets",
            "mimeType": "application/json",
        },
        {
            "uri": "waybar://docs/mcp",
            "name": "MCP docs",
            "description": "docs/mcp.md",
            "mimeType": "text/markdown",
        },
        {
            "uri": "waybar://docs/readme",
            "name": "README",
            "description": "Repository README.md",
            "mimeType": "text/markdown",
        },
    ]
    for name in theme_ops.list_themes(paths).get("themes", []):
        resources.append(
            {
                "uri": f"waybar://themes/{name}",
                "name": f"Theme {name}",
                "mimeType": "application/json",
            }
        )
    for mid in MANIFEST_FILES:
        resources.append(
            {
                "uri": f"waybar://manifests/{mid}",
                "name": f"Manifest {mid}",
                "mimeType": "application/json",
            }
        )
    return resources


def read_resource(paths: WaybarPaths, uri: str) -> dict[str, Any]:
    try:
        text, mime = _read(paths, uri)
    except Exception as exc:  # noqa: BLE001
        return {
            "contents": [
                {
                    "uri": uri,
                    "mimeType": "text/plain",
                    "text": f"Error: {exc}",
                }
            ],
            "_error": True,
            "message": str(exc),
        }
    return {
        "contents": [
            {
                "uri": uri,
                "mimeType": mime,
                "text": text,
            }
        ]
    }


def _read(paths: WaybarPaths, uri: str) -> tuple[str, str]:
    if ".." in uri:
        raise ValueError("invalid URI")
    if uri == "waybar://overview":
        return json.dumps(settings_ops.overview(paths), indent=2), "application/json"
    if uri == "waybar://settings":
        return (
            json.dumps(settings_ops.get_settings(paths), indent=2, ensure_ascii=False),
            "application/json",
        )
    if uri == "waybar://settings-raw":
        return (
            json.dumps(
                {
                    "sot": str(paths.settings_jsonc),
                    "note": "Edit via tools; programmatic writes drop JSONC comments.",
                },
                indent=2,
            ),
            "application/json",
        )
    if uri == "waybar://themes":
        return json.dumps(theme_ops.list_themes(paths), indent=2), "application/json"
    if uri.startswith("waybar://themes/"):
        name = uri.removeprefix("waybar://themes/")
        return (
            json.dumps(theme_ops.get_theme(paths, name), indent=2, ensure_ascii=False),
            "application/json",
        )
    if uri.startswith("waybar://manifests/"):
        mid = uri.removeprefix("waybar://manifests/")
        data = manifest_ops.get_manifest(paths, mid)
        if isinstance(data, str):
            return data, "text/plain"
        return json.dumps(data, indent=2, ensure_ascii=False), "application/json"
    if uri == "waybar://docs/mcp":
        doc = paths.home / "docs" / "mcp.md"
        if not doc.is_file():
            raise FileNotFoundError("docs/mcp.md not found")
        return doc.read_text(encoding="utf-8"), "text/markdown"
    if uri == "waybar://docs/readme":
        doc = paths.home / "README.md"
        if not doc.is_file():
            raise FileNotFoundError("README.md not found")
        return doc.read_text(encoding="utf-8"), "text/markdown"
    raise ValueError(f"unknown resource URI: {uri}")


def resource_error_result(message: str) -> dict[str, Any]:
    return error_result(message)
