"""Secrets metadata only — never return live secret values."""

from __future__ import annotations

import stat
from typing import Any

from jsonc_util import load_jsonc, structure_only
from paths import WaybarPaths


def secrets_status(paths: WaybarPaths) -> dict[str, Any]:
    path = paths.secrets_jsonc
    result: dict[str, Any] = {
        "path": str(path),
        "exists": path.is_file(),
        "example": str(paths.secrets_example),
        "example_exists": paths.secrets_example.is_file(),
    }
    if not path.is_file():
        return result
    mode = path.stat().st_mode
    result["mode"] = oct(stat.S_IMODE(mode))
    result["world_readable"] = bool(mode & stat.S_IROTH)
    try:
        data = load_jsonc(str(path))
        result["structure"] = structure_only(data)
    except (OSError, ValueError) as exc:
        result["structure_error"] = str(exc)
    return result


def secrets_example(paths: WaybarPaths) -> str:
    if not paths.secrets_example.is_file():
        raise FileNotFoundError(f"missing: {paths.secrets_example}")
    return paths.secrets_example.read_text(encoding="utf-8")
