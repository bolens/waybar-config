"""Register the Waybar MCP server with common AI clients."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def server_config(script_path: Path) -> dict[str, object]:
    return {
        "command": "python3",
        "args": [str(script_path.resolve())],
    }


def register_mcp(script_path: Path) -> int:
    home = Path(os.path.expanduser("~"))
    if sys.platform == "win32":
        claude_path = Path(os.environ.get("APPDATA", "")) / "Claude" / "claude_desktop_config.json"
    else:
        claude_path = home / ".config" / "Claude" / "claude_desktop_config.json"

    configs = [
        ("Claude Desktop", claude_path, "mcpServers"),
        ("Windsurf", home / ".codeium" / "windsurf" / "mcp_config.json", "mcpServers"),
        ("Cursor", home / ".cursor" / "mcp.json", "mcpServers"),
    ]

    server_name = "waybar"
    cfg = server_config(script_path)
    registered_any = False

    for label, path, key in configs:
        dir_path = path.parent
        if not dir_path.is_dir():
            continue

        print(f"Registering Waybar MCP server in {label}...")
        data: dict = {}
        if path.is_file():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except Exception as exc:  # noqa: BLE001 — report and continue
                print(f"  Warning: failed to read {path}: {exc}. Creating new.")

        if key not in data or not isinstance(data[key], dict):
            data[key] = {}

        existing = data[key].get(server_name)
        if (
            isinstance(existing, dict)
            and existing.get("command") == cfg["command"]
            and existing.get("args") == cfg["args"]
        ):
            print(f"  Already registered in {label}.")
            registered_any = True
            continue

        data[key][server_name] = cfg
        try:
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
            print(f"  Successfully registered in {label} config: {path}")
            registered_any = True
        except OSError as exc:
            print(f"  Error: failed to write {path}: {exc}")

    snippet = {"mcpServers": {server_name: cfg}}
    print("\nManual config snippet (any MCP host):")
    print(json.dumps(snippet, indent=2))

    if not registered_any:
        print(
            "\nNo active config directories found (Claude Desktop, Windsurf, or Cursor)."
        )
        print("Paste the snippet above into your MCP client's config file.")
        return 1

    print("\nRegistration check completed successfully.")
    print("Restart Cursor / Claude Desktop / Windsurf so the MCP server appears.")
    print("See docs/mcp.md for tool details and troubleshooting.")
    return 0
