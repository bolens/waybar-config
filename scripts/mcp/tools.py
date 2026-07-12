"""MCP tool schemas and dispatch."""

from __future__ import annotations

from typing import Any, Callable

import catalog_ops
import layout_ops
import manifest_ops
import run_ops
import secrets_ops
import settings_ops
import theme_ops
from paths import WaybarPaths
from protocol import error_result, json_result, text_result


def _ok_run(result: dict[str, Any]) -> dict[str, Any]:
    payload = {
        "ok": result.get("ok", True),
        "returncode": result.get("returncode"),
        "output": result.get("output", ""),
    }
    if result.get("skipped"):
        payload["skipped"] = True
    return json_result(payload, is_error=not payload["ok"])


def get_tools_list() -> list[dict[str, Any]]:
    def tool(name: str, description: str, properties: dict, required: list | None = None):
        schema: dict[str, Any] = {"type": "object", "properties": properties}
        if required:
            schema["required"] = required
        return {"name": name, "description": description, "inputSchema": schema}

    return [
        tool("waybar_overview", "Compact overview of the Waybar config.", {}),
        tool(
            "waybar_describe",
            "Agent playbook: SoT paths, generate flow, secrets rules.",
            {},
        ),
        tool("waybar_schema", "Top-level settings keys with short descriptions.", {}),
        tool(
            "waybar_search",
            "Search settings keys/values by substring.",
            {
                "query": {"type": "string", "description": "Substring to search."},
                "limit": {"type": "integer", "description": "Max hits (default 50)."},
            },
            ["query"],
        ),
        tool(
            "waybar_get_settings",
            "Read settings (optional dotted path). Secrets excluded by default; secret keys redacted.",
            {
                "path": {"type": "string", "description": "Dotted path, e.g. theme.preset"},
                "include_secrets": {
                    "type": "boolean",
                    "description": "Merge secrets overlay (values still redacted).",
                },
            },
        ),
        tool(
            "waybar_diff_settings",
            "Dry-run deep-merge preview without writing.",
            {"overlay": {"type": "object", "description": "Object to merge into settings."}},
            ["overlay"],
        ),
        tool(
            "waybar_patch_settings",
            "Deep-merge into waybar-settings.jsonc. Comments are lost on write.",
            {
                "overlay": {"type": "object"},
                "dry_run": {"type": "boolean"},
            },
            ["overlay"],
        ),
        tool(
            "waybar_set_path",
            "Set one dotted settings path to a JSON value.",
            {
                "path": {"type": "string"},
                "value": {},
                "dry_run": {"type": "boolean"},
            },
            ["path", "value"],
        ),
        tool(
            "waybar_unset_path",
            "Delete one dotted settings path.",
            {"path": {"type": "string"}, "dry_run": {"type": "boolean"}},
            ["path"],
        ),
        tool("waybar_backup_settings", "Backup settings SoT to cache + data/.", {}),
        tool(
            "waybar_restore_settings",
            "Restore settings from an allowlisted backup path.",
            {"backup_path": {"type": "string"}},
            ["backup_path"],
        ),
        tool("waybar_list_backups", "List MCP settings backups.", {}),
        tool("waybar_list_themes", "List theme presets and active theme.", {}),
        tool(
            "waybar_get_theme",
            "Read a theme preset JSONC.",
            {"name": {"type": "string"}},
            ["name"],
        ),
        tool(
            "waybar_set_theme",
            "Set theme.mode / theme.preset / wallpaper fields.",
            {
                "mode": {"type": "string", "enum": ["static", "preset", "wallpaper"]},
                "preset": {"type": "string"},
                "wallpaper": {"type": "object"},
            },
        ),
        tool(
            "waybar_apply_preset",
            "Apply preset colors into theme (default mode=static).",
            {
                "name": {"type": "string"},
                "keep_preset_mode": {"type": "boolean"},
            },
            ["name"],
        ),
        tool(
            "waybar_write_theme",
            "Create/update data/themes/<name>.jsonc.",
            {
                "name": {"type": "string"},
                "body": {"type": "object"},
                "confirm_overwrite": {"type": "boolean"},
            },
            ["name", "body"],
        ),
        tool("waybar_list_groups", "List groups with modules/drawers.", {}),
        tool(
            "waybar_get_group",
            "Get one group.",
            {"name": {"type": "string"}},
            ["name"],
        ),
        tool(
            "waybar_set_group_modules",
            "Replace a group's modules array.",
            {
                "name": {"type": "string"},
                "modules": {"type": "array", "items": {"type": "string"}},
            },
            ["name", "modules"],
        ),
        tool(
            "waybar_get_layout",
            "Get layouts (optional bar: top|bottom).",
            {"bar": {"type": "string", "enum": ["top", "bottom"]}},
        ),
        tool(
            "waybar_set_layout_modules",
            "Set modules_left/center/right for a bar.",
            {
                "bar": {"type": "string", "enum": ["top", "bottom"]},
                "side": {
                    "type": "string",
                    "enum": ["modules_left", "modules_center", "modules_right"],
                },
                "modules": {"type": "array", "items": {"type": "string"}},
            },
            ["bar", "side", "modules"],
        ),
        tool("waybar_get_bars", "Read bars.* settings.", {}),
        tool(
            "waybar_set_bars",
            "Patch bars.* fields.",
            {"patch": {"type": "object"}},
            ["patch"],
        ),
        tool("waybar_get_intervals", "Read module_intervals.", {}),
        tool(
            "waybar_set_interval",
            "Set one module_intervals key.",
            {
                "key": {"type": "string"},
                "value": {"description": "'once' or integer seconds"},
            },
            ["key", "value"],
        ),
        tool("waybar_get_signals", "Read signals map.", {}),
        tool(
            "waybar_set_signal",
            "Set one signal number.",
            {"key": {"type": "string"}, "value": {"type": "integer"}},
            ["key", "value"],
        ),
        tool("waybar_list_profiles", "List data/profiles/*.jsonc.", {}),
        tool(
            "waybar_get_profile",
            "Read a profile.",
            {"name": {"type": "string"}},
            ["name"],
        ),
        tool(
            "waybar_apply_profile",
            "Deep-merge a profile into settings.",
            {"name": {"type": "string"}, "dry_run": {"type": "boolean"}},
            ["name"],
        ),
        tool("waybar_list_manifests", "List allowlisted data manifests.", {}),
        tool(
            "waybar_get_manifest",
            "Read a manifest by id.",
            {"id": {"type": "string"}},
            ["id"],
        ),
        tool(
            "waybar_patch_manifest",
            "Deep-merge patch an allowlisted manifest (not secrets).",
            {
                "id": {"type": "string"},
                "overlay": {"type": "object"},
                "dry_run": {"type": "boolean"},
            },
            ["id", "overlay"],
        ),
        tool("waybar_list_modules", "List generated module ids.", {}),
        tool(
            "waybar_get_module",
            "Get one generated module definition.",
            {"id": {"type": "string"}},
            ["id"],
        ),
        tool("waybar_list_generated", "List *.generated.* relative paths.", {}),
        tool(
            "waybar_read_generated",
            "Read one generated artifact (relative path).",
            {"path": {"type": "string"}},
            ["path"],
        ),
        tool("waybar_list_scripts", "Index scripts/ by domain folder.", {}),
        tool(
            "waybar_find_script",
            "Find scripts matching a module id / basename.",
            {"query": {"type": "string"}},
            ["query"],
        ),
        tool("waybar_generate", "Run make generate.", {}),
        tool("waybar_validate", "Run validate-generated-config.sh.", {}),
        tool("waybar_check_drift", "Run check-generated-drift.sh.", {}),
        tool(
            "waybar_check",
            "Run a Makefile check subset (syntax|python|validate|fast|contracts|ruff).",
            {
                "subset": {
                    "type": "string",
                    "enum": ["syntax", "python", "validate", "fast", "contracts", "ruff"],
                }
            },
            ["subset"],
        ),
        tool("waybar_status", "systemd --user unit status + pgrep waybar.", {}),
        tool(
            "waybar_restart",
            "Restart waybar.service (requires confirm=true).",
            {"confirm": {"type": "boolean"}},
            ["confirm"],
        ),
        tool(
            "waybar_secrets_status",
            "Secrets file metadata/structure only (no values).",
            {},
        ),
        tool(
            "waybar_secrets_example",
            "Return waybar-secrets.example.jsonc contents.",
            {},
        ),
    ]


def handle_tool_call(
    paths: WaybarPaths, tool_name: str, arguments: dict[str, Any] | None
) -> dict[str, Any]:
    # Schemas in get_tools_list() must stay in sync with these handler keys
    # (and all_tool_names()). Adding a tool requires both sides.
    args = arguments or {}
    handlers: dict[str, Callable[[], dict[str, Any]]] = {
        "waybar_overview": lambda: json_result(settings_ops.overview(paths)),
        "waybar_describe": lambda: text_result(settings_ops.describe(paths)),
        "waybar_schema": lambda: json_result(settings_ops.schema()),
        "waybar_search": lambda: json_result(
            settings_ops.search_settings(
                paths, str(args.get("query", "")), limit=int(args.get("limit", 50))
            )
        ),
        "waybar_get_settings": lambda: json_result(
            settings_ops.get_settings(
                paths,
                args.get("path"),
                include_secrets=bool(args.get("include_secrets", False)),
            )
        ),
        "waybar_diff_settings": lambda: json_result(
            settings_ops.diff_settings(paths, args.get("overlay") or {})
        ),
        "waybar_patch_settings": lambda: json_result(
            settings_ops.patch_settings(
                paths,
                args.get("overlay") or {},
                dry_run=bool(args.get("dry_run", False)),
            )
        ),
        "waybar_set_path": lambda: json_result(
            settings_ops.set_settings_path(
                paths,
                str(args.get("path", "")),
                args.get("value"),
                dry_run=bool(args.get("dry_run", False)),
            )
        ),
        "waybar_unset_path": lambda: json_result(
            settings_ops.unset_settings_path(
                paths,
                str(args.get("path", "")),
                dry_run=bool(args.get("dry_run", False)),
            )
        ),
        "waybar_backup_settings": lambda: json_result(
            settings_ops.backup_settings(paths)
        ),
        "waybar_restore_settings": lambda: json_result(
            settings_ops.restore_settings(paths, str(args.get("backup_path", "")))
        ),
        "waybar_list_backups": lambda: json_result(settings_ops.list_backups(paths)),
        "waybar_list_themes": lambda: json_result(theme_ops.list_themes(paths)),
        "waybar_get_theme": lambda: json_result(
            theme_ops.get_theme(paths, str(args.get("name", "")))
        ),
        "waybar_set_theme": lambda: json_result(
            theme_ops.set_theme(
                paths,
                mode=args.get("mode"),
                preset=args.get("preset"),
                wallpaper=args.get("wallpaper"),
            )
        ),
        "waybar_apply_preset": lambda: json_result(
            theme_ops.apply_preset(
                paths,
                str(args.get("name", "")),
                keep_preset_mode=bool(args.get("keep_preset_mode", False)),
            )
        ),
        "waybar_write_theme": lambda: json_result(
            theme_ops.write_theme(
                paths,
                str(args.get("name", "")),
                args.get("body") or {},
                confirm_overwrite=bool(args.get("confirm_overwrite", False)),
            )
        ),
        "waybar_list_groups": lambda: json_result(layout_ops.list_groups(paths)),
        "waybar_get_group": lambda: json_result(
            layout_ops.get_group(paths, str(args.get("name", "")))
        ),
        "waybar_set_group_modules": lambda: json_result(
            layout_ops.set_group_modules(
                paths, str(args.get("name", "")), args.get("modules") or []
            )
        ),
        "waybar_get_layout": lambda: json_result(
            layout_ops.get_layout(paths, args.get("bar"))
        ),
        "waybar_set_layout_modules": lambda: json_result(
            layout_ops.set_layout_modules(
                paths,
                str(args.get("bar", "")),
                str(args.get("side", "")),
                args.get("modules") or [],
            )
        ),
        "waybar_get_bars": lambda: json_result(layout_ops.get_bars(paths)),
        "waybar_set_bars": lambda: json_result(
            layout_ops.set_bars(paths, args.get("patch") or {})
        ),
        "waybar_get_intervals": lambda: json_result(layout_ops.get_intervals(paths)),
        "waybar_set_interval": lambda: json_result(
            layout_ops.set_interval(paths, str(args.get("key", "")), args.get("value"))
        ),
        "waybar_get_signals": lambda: json_result(layout_ops.get_signals(paths)),
        "waybar_set_signal": lambda: json_result(
            layout_ops.set_signal(
                paths, str(args.get("key", "")), int(args.get("value"))
            )
        ),
        "waybar_list_profiles": lambda: json_result(manifest_ops.list_profiles(paths)),
        "waybar_get_profile": lambda: json_result(
            manifest_ops.get_profile(paths, str(args.get("name", "")))
        ),
        "waybar_apply_profile": lambda: json_result(
            manifest_ops.apply_profile(
                paths,
                str(args.get("name", "")),
                dry_run=bool(args.get("dry_run", False)),
            )
        ),
        "waybar_list_manifests": lambda: json_result(
            manifest_ops.list_manifests(paths)
        ),
        "waybar_get_manifest": lambda: json_result(
            manifest_ops.get_manifest(paths, str(args.get("id", "")))
        ),
        "waybar_patch_manifest": lambda: json_result(
            manifest_ops.patch_manifest(
                paths,
                str(args.get("id", "")),
                args.get("overlay") or {},
                dry_run=bool(args.get("dry_run", False)),
            )
        ),
        "waybar_list_modules": lambda: json_result(catalog_ops.list_modules(paths)),
        "waybar_get_module": lambda: json_result(
            catalog_ops.get_module(paths, str(args.get("id", "")))
        ),
        "waybar_list_generated": lambda: json_result(
            catalog_ops.list_generated(paths)
        ),
        "waybar_read_generated": lambda: text_result(
            catalog_ops.read_generated(paths, str(args.get("path", "")))
        ),
        "waybar_list_scripts": lambda: json_result(catalog_ops.list_scripts(paths)),
        "waybar_find_script": lambda: json_result(
            catalog_ops.find_script(paths, str(args.get("query", "")))
        ),
        "waybar_generate": lambda: _ok_run(run_ops.generate(paths)),
        "waybar_validate": lambda: _ok_run(run_ops.validate(paths)),
        "waybar_check_drift": lambda: _ok_run(run_ops.check_drift(paths)),
        "waybar_check": lambda: _ok_run(
            run_ops.check(paths, str(args.get("subset", "")))
        ),
        "waybar_status": lambda: json_result(run_ops.status(paths)),
        "waybar_restart": lambda: _ok_run(
            run_ops.restart(confirm=bool(args.get("confirm", False)))
        ),
        "waybar_secrets_status": lambda: json_result(
            secrets_ops.secrets_status(paths)
        ),
        "waybar_secrets_example": lambda: text_result(
            secrets_ops.secrets_example(paths)
        ),
    }

    if tool_name not in handlers:
        return error_result(f"Unknown tool: {tool_name}")

    try:
        return handlers[tool_name]()
    except Exception as exc:  # noqa: BLE001 — surface to MCP client
        return error_result(f"Error: {exc}")


def all_tool_names() -> list[str]:
    return [t["name"] for t in get_tools_list()]
