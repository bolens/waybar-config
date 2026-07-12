"""JSON-RPC / MCP response helpers."""

from __future__ import annotations

import json
import sys
from typing import Any

SERVER_NAME = "waybar-mcp"
SERVER_VERSION = "1.0.0"
PROTOCOL_VERSION = "2024-11-05"


def log(msg: str) -> None:
    sys.stderr.write(f"[MCP LOG] {msg}\n")
    sys.stderr.flush()


def text_result(text: str, *, is_error: bool = False) -> dict[str, Any]:
    return {
        "content": [{"type": "text", "text": text}],
        "isError": is_error,
    }


def json_result(data: Any, *, is_error: bool = False) -> dict[str, Any]:
    return text_result(
        json.dumps(data, indent=2, ensure_ascii=False),
        is_error=is_error,
    )


def error_result(message: str) -> dict[str, Any]:
    return text_result(message, is_error=True)


def write_response(resp: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def capabilities() -> dict[str, Any]:
    return {
        "tools": {},
        "resources": {},
        "prompts": {},
    }


def server_info() -> dict[str, Any]:
    return {"name": SERVER_NAME, "version": SERVER_VERSION}
