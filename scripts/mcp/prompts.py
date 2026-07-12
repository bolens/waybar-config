"""MCP prompts for common Waybar config workflows."""

from __future__ import annotations

from typing import Any


def list_prompts() -> list[dict[str, Any]]:
    return [
        {
            "name": "customize_theme",
            "description": "Switch theme mode/preset and regenerate.",
            "arguments": [
                {
                    "name": "preset",
                    "description": "Theme preset name (e.g. nord, gruvbox)",
                    "required": False,
                },
                {
                    "name": "mode",
                    "description": "static | preset | wallpaper",
                    "required": False,
                },
            ],
        },
        {
            "name": "minimal_profile",
            "description": "Apply minimal-groups profile, generate, validate.",
            "arguments": [],
        },
        {
            "name": "add_module_to_group",
            "description": "Insert a module id into a group modules list.",
            "arguments": [
                {"name": "group", "description": "Group name", "required": True},
                {
                    "name": "module_id",
                    "description": "Module id (e.g. custom/weather)",
                    "required": True,
                },
                {
                    "name": "position",
                    "description": "append | prepend | index:N",
                    "required": False,
                },
            ],
        },
        {
            "name": "tune_intervals",
            "description": "Update module_intervals keys then generate.",
            "arguments": [
                {
                    "name": "updates",
                    "description": "JSON object of key -> once|seconds",
                    "required": True,
                }
            ],
        },
        {
            "name": "floating_bar",
            "description": "Enable floating island bar geometry.",
            "arguments": [
                {
                    "name": "margin_top",
                    "description": "Top margin px",
                    "required": False,
                },
            ],
        },
        {
            "name": "homelab_targets",
            "description": "Edit homelab.targets health probes.",
            "arguments": [
                {
                    "name": "targets",
                    "description": "JSON array/object of targets",
                    "required": True,
                }
            ],
        },
        {
            "name": "after_edit_workflow",
            "description": "Backup → generate → validate → restart checklist.",
            "arguments": [],
        },
    ]


def get_prompt(name: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
    args = arguments or {}
    prompts = {p["name"]: p for p in list_prompts()}
    if name not in prompts:
        raise KeyError(f"unknown prompt: {name}")

    text = _prompt_text(name, args)
    return {
        "description": prompts[name]["description"],
        "messages": [
            {
                "role": "user",
                "content": {"type": "text", "text": text},
            }
        ],
    }


def _prompt_text(name: str, args: dict[str, Any]) -> str:
    if name == "customize_theme":
        preset = args.get("preset", "<choose from waybar_list_themes>")
        mode = args.get("mode", "preset")
        return f"""Customize the Waybar theme.

1. Call waybar_backup_settings.
2. Call waybar_list_themes, then waybar_set_theme with mode={mode!r} and preset={preset!r}
   (or waybar_apply_preset with name={preset!r}).
3. Call waybar_generate, then waybar_validate.
4. Optionally waybar_restart with confirm=true.
"""

    if name == "minimal_profile":
        return """Apply the minimal/laptop profile.

1. waybar_backup_settings
2. waybar_list_profiles then waybar_apply_profile with name="minimal-groups" (dry_run first if unsure)
3. waybar_generate
4. waybar_validate
5. waybar_restart with confirm=true when ready
"""

    if name == "add_module_to_group":
        group = args.get("group", "<group>")
        module_id = args.get("module_id", "<module_id>")
        position = args.get("position", "append")
        return f"""Add a module to a group.

1. waybar_get_group name={group!r}
2. Build a new modules array inserting {module_id!r} at position={position!r}
3. waybar_set_group_modules name={group!r} modules=[...]
4. waybar_generate && waybar_validate
"""

    if name == "tune_intervals":
        updates = args.get("updates", "{}")
        return f"""Tune module_intervals.

Updates: {updates}

For each key/value, call waybar_set_interval. Then waybar_generate and waybar_validate.
"""

    if name == "floating_bar":
        margin = args.get("margin_top", 8)
        return f"""Enable floating bar chrome.

1. waybar_set_bars patch={{"floating": true, "margin_top": {margin}, "margin_right": 12, "margin_left": 12}}
2. waybar_generate && waybar_validate
3. waybar_restart confirm=true
"""

    if name == "homelab_targets":
        targets = args.get("targets", "[]")
        return f"""Update homelab health targets.

1. waybar_get_settings path="homelab"
2. waybar_set_path path="homelab.targets" value={targets}
3. waybar_generate && waybar_validate
"""

    if name == "after_edit_workflow":
        return """After any settings edit:

1. waybar_backup_settings (if not already done)
2. waybar_generate
3. waybar_validate
4. waybar_check_drift if committing generated artifacts
5. waybar_restart with confirm=true to reload the bar
"""

    raise KeyError(name)
