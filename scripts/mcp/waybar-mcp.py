#!/usr/bin/env python3
"""
Model Context Protocol (MCP) server for this Waybar config tree.

Stdlib-only JSON-RPC over stdin/stdout. Register with:
  python3 scripts/mcp/waybar-mcp.py --register
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Allow `python3 scripts/mcp/waybar-mcp.py` without installing a package.
_MCP_DIR = Path(__file__).resolve().parent
if str(_MCP_DIR) not in sys.path:
    sys.path.insert(0, str(_MCP_DIR))

from paths import WaybarPaths, resolve_waybar_home  # noqa: E402
from protocol import (  # noqa: E402
    PROTOCOL_VERSION,
    capabilities,
    log,
    server_info,
    write_response,
)
from prompts import get_prompt, list_prompts  # noqa: E402
from register_mcp import register_mcp  # noqa: E402
from resources import list_resources, read_resource  # noqa: E402
from tools import get_tools_list, handle_tool_call  # noqa: E402


def write_error(msg_id: str | int | None, code: int, message: str) -> None:
    write_response(
        {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Model Context Protocol (MCP) server for Waybar config."
    )
    parser.add_argument(
        "--register",
        "-r",
        action="store_true",
        help="Register with Claude Desktop, Windsurf, and Cursor.",
    )
    parser.add_argument(
        "-V",
        "--version",
        action="store_true",
        help="Show version information.",
    )
    parser.add_argument(
        "--waybar-home",
        default=None,
        help="Override WAYBAR_HOME (default: env, then checkout root).",
    )
    args = parser.parse_args()

    if args.version:
        info = server_info()
        print(f"{info['name']} {info['version']}")
        return

    if args.register:
        rc = register_mcp(Path(__file__))
        raise SystemExit(rc)

    home = resolve_waybar_home(args.waybar_home or os.environ.get("WAYBAR_HOME"))
    paths = WaybarPaths(home)
    log(f"Waybar MCP server started (WAYBAR_HOME={paths.home})")

    while True:
        msg_id = None
        try:
            line = sys.stdin.readline()
            if not line:
                break
            req = json.loads(line)
            if not isinstance(req, dict):
                write_error(None, -32600, "Invalid request")
                continue
            raw_id = req.get("id")
            valid_id = type(raw_id) in (str, int)
            msg_id = raw_id if valid_id else None
            if (
                req.get("jsonrpc") != "2.0"
                or not isinstance(req.get("method"), str)
                or ("id" in req and not valid_id)
            ):
                write_error(msg_id, -32600, "Invalid request")
                continue
            # Notifications never receive responses or invoke request-only operations.
            if "id" not in req:
                continue
            if not isinstance(req.get("params", {}), dict):
                write_error(msg_id, -32602, "params must be an object")
                continue
            method = req.get("method")

            if method == "initialize":
                write_response(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "result": {
                            "protocolVersion": PROTOCOL_VERSION,
                            "capabilities": capabilities(),
                            "serverInfo": server_info(),
                        },
                    }
                )
            elif method == "ping":
                write_response({"jsonrpc": "2.0", "id": msg_id, "result": {}})
            elif method == "tools/list":
                write_response(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "result": {"tools": get_tools_list()},
                    }
                )
            elif method == "tools/call":
                params = req.get("params") or {}
                result = handle_tool_call(
                    paths,
                    params.get("name"),
                    params.get("arguments", {}),
                )
                write_response({"jsonrpc": "2.0", "id": msg_id, "result": result})
            elif method == "resources/list":
                write_response(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "result": {"resources": list_resources(paths)},
                    }
                )
            elif method == "resources/read":
                params = req.get("params") or {}
                uri = params.get("uri", "")
                result = read_resource(paths, uri)
                if result.pop("_error", False):
                    write_response(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "error": {
                                "code": -32000,
                                "message": result.get("message", "resource error"),
                            },
                        }
                    )
                else:
                    write_response({"jsonrpc": "2.0", "id": msg_id, "result": result})
            elif method == "prompts/list":
                write_response(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "result": {"prompts": list_prompts()},
                    }
                )
            elif method == "prompts/get":
                params = req.get("params") or {}
                try:
                    result = get_prompt(
                        params.get("name", ""),
                        params.get("arguments", {}),
                    )
                    write_response({"jsonrpc": "2.0", "id": msg_id, "result": result})
                except Exception as exc:  # noqa: BLE001
                    write_response(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "error": {"code": -32602, "message": str(exc)},
                        }
                    )
            else:
                if msg_id is not None:
                    write_response(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "error": {
                                "code": -32601,
                                "message": f"Method not found: {method}",
                            },
                        }
                    )
        except json.JSONDecodeError:
            write_error(None, -32700, "Parse error")
        except Exception as exc:  # noqa: BLE001
            log(f"Error handling request: {exc}")
            write_error(msg_id, -32603, "Internal error")


if __name__ == "__main__":
    main()
