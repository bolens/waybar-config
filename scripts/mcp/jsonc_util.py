"""JSONC load/dump, deep merge, and dotted-path helpers (stdlib only)."""

from __future__ import annotations

import json
import re
from copy import deepcopy
from typing import Any


_SECRET_KEY_RE = re.compile(
    r"(pass|password|token|secret|api[_-]?key|credential)", re.IGNORECASE
)


def strip_jsonc_comments(text: str) -> str:
    """Strip /* */ and // comments (URL-safe: do not strip // after :)."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"(?<!:)//.*?$", "", text, flags=re.M)
    return text


def loads_jsonc(text: str) -> Any:
    return json.loads(strip_jsonc_comments(text))


def load_jsonc(path: str) -> Any:
    with open(path, encoding="utf-8") as f:
        return loads_jsonc(f.read())


def dump_json(data: Any, path: str, *, indent: int = 2) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=indent, ensure_ascii=False)
        f.write("\n")


def deep_merge(base: Any, overlay: Any) -> Any:
    """Deep-merge overlay into a copy of base. Dicts merge; other types replace."""
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for key, value in overlay.items():
            if key in out:
                out[key] = deep_merge(out[key], value)
            else:
                out[key] = deepcopy(value)
        return out
    return deepcopy(overlay)


def parse_path(path: str) -> list[str]:
    path = path.strip().lstrip(".")
    if not path:
        return []
    return [p for p in path.split(".") if p]


def get_path(data: Any, path: str, default: Any = None) -> Any:
    keys = parse_path(path)
    cur: Any = data
    for key in keys:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def set_path(data: dict[str, Any], path: str, value: Any) -> dict[str, Any]:
    keys = parse_path(path)
    if not keys:
        raise ValueError("path must not be empty")
    out = deepcopy(data)
    cur: Any = out
    for key in keys[:-1]:
        if key not in cur or not isinstance(cur[key], dict):
            cur[key] = {}
        cur = cur[key]
    cur[keys[-1]] = value
    return out


def unset_path(data: dict[str, Any], path: str) -> dict[str, Any]:
    keys = parse_path(path)
    if not keys:
        raise ValueError("cannot unset root")
    out = deepcopy(data)
    cur: Any = out
    for key in keys[:-1]:
        if not isinstance(cur, dict) or key not in cur:
            raise KeyError(f"path not found: {path}")
        cur = cur[key]
    if not isinstance(cur, dict) or keys[-1] not in cur:
        raise KeyError(f"path not found: {path}")
    del cur[keys[-1]]
    return out


def redact_secrets(data: Any) -> Any:
    """Replace secret-looking leaf values with redaction markers."""
    if isinstance(data, dict):
        out: dict[str, Any] = {}
        for key, value in data.items():
            if isinstance(value, (dict, list)):
                out[key] = redact_secrets(value)
            elif _SECRET_KEY_RE.search(str(key)):
                out[key] = "[REDACTED]"
            else:
                out[key] = value
        return out
    if isinstance(data, list):
        return [redact_secrets(item) for item in data]
    return data


def structure_only(data: Any) -> Any:
    """Keep dict/list shape; replace leaves with type names (no secret values)."""
    if isinstance(data, dict):
        return {k: structure_only(v) for k, v in data.items()}
    if isinstance(data, list):
        if not data:
            return []
        return [structure_only(data[0])]
    return type(data).__name__


def path_looks_secret(path: str) -> bool:
    return bool(_SECRET_KEY_RE.search(path))


def search_tree(
    data: Any,
    query: str,
    *,
    prefix: str = "",
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Substring search over keys and string values."""
    q = query.lower()
    hits: list[dict[str, Any]] = []

    def walk(node: Any, path: str) -> None:
        if len(hits) >= limit:
            return
        if isinstance(node, dict):
            for key, value in node.items():
                child = f"{path}.{key}" if path else key
                if q in key.lower():
                    hits.append({"path": child, "match": "key", "snippet": key})
                walk(value, child)
                if len(hits) >= limit:
                    return
        elif isinstance(node, list):
            for i, value in enumerate(node):
                walk(value, f"{path}[{i}]")
                if len(hits) >= limit:
                    return
        elif isinstance(node, str) and q in node.lower():
            snippet = node if len(node) <= 120 else node[:117] + "..."
            hits.append({"path": path, "match": "value", "snippet": snippet})

    walk(data, prefix)
    return hits
