"""Re-export shared JSONC helpers from scripts/lib (kept for MCP import paths)."""

from __future__ import annotations

import importlib.util
from pathlib import Path

_LIB_FILE = Path(__file__).resolve().parent.parent / "lib" / "jsonc_util.py"
_spec = importlib.util.spec_from_file_location("waybar_lib_jsonc_util", _LIB_FILE)
if _spec is None or _spec.loader is None:
    raise ImportError(f"cannot load shared jsonc_util from {_LIB_FILE}")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

deep_merge = _mod.deep_merge
dump_json = _mod.dump_json
get_path = _mod.get_path
load_jsonc = _mod.load_jsonc
loads_jsonc = _mod.loads_jsonc
parse_path = _mod.parse_path
path_looks_secret = _mod.path_looks_secret
redact_secrets = _mod.redact_secrets
search_tree = _mod.search_tree
set_path = _mod.set_path
strip_jsonc_comments = _mod.strip_jsonc_comments
structure_only = _mod.structure_only
unset_path = _mod.unset_path

__all__ = [
    "deep_merge",
    "dump_json",
    "get_path",
    "load_jsonc",
    "loads_jsonc",
    "parse_path",
    "path_looks_secret",
    "redact_secrets",
    "search_tree",
    "set_path",
    "strip_jsonc_comments",
    "structure_only",
    "unset_path",
]
