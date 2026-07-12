"""Profiles and data manifests."""

from __future__ import annotations

from typing import Any

from jsonc_util import deep_merge, dump_json, load_jsonc
from paths import MANIFEST_FILES, WaybarPaths
from settings_ops import load_settings, write_settings


def list_profiles(paths: WaybarPaths) -> list[str]:
    if not paths.profiles_dir.is_dir():
        return []
    return sorted(p.stem for p in paths.profiles_dir.glob("*.jsonc"))


def get_profile(paths: WaybarPaths, name: str) -> Any:
    path = paths.profile_file(name)
    if not path.is_file():
        raise FileNotFoundError(f"profile not found: {name}")
    return load_jsonc(str(path))


def apply_profile(
    paths: WaybarPaths, name: str, *, dry_run: bool = False
) -> dict[str, Any]:
    overlay = get_profile(paths, name)
    if not isinstance(overlay, dict):
        raise ValueError("profile root must be an object")
    before = load_settings(paths)
    after = deep_merge(before, overlay)
    if not dry_run:
        write_settings(paths, after)
    return {
        "profile": name,
        "dry_run": dry_run,
        "before": before,
        "after": after,
    }


def list_manifests(paths: WaybarPaths) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for mid, rel in MANIFEST_FILES.items():
        path = paths.home / rel
        out[mid] = {"path": str(path), "exists": path.is_file()}
    return out


def get_manifest(paths: WaybarPaths, manifest_id: str) -> Any:
    path = paths.manifest_file(manifest_id)
    if not path.is_file():
        raise FileNotFoundError(f"manifest not found: {manifest_id}")
    if path.suffix in {".jsonc", ".json"}:
        return load_jsonc(str(path))
    return path.read_text(encoding="utf-8")


def patch_manifest(
    paths: WaybarPaths,
    manifest_id: str,
    overlay: dict[str, Any],
    *,
    dry_run: bool = False,
) -> dict[str, Any]:
    if manifest_id == "secrets-example":
        raise ValueError("refusing to patch secrets-example via MCP")
    path = paths.manifest_file(manifest_id)
    if not path.is_file():
        raise FileNotFoundError(f"manifest not found: {manifest_id}")
    before = load_jsonc(str(path))
    if not isinstance(before, dict) or not isinstance(overlay, dict):
        raise ValueError("manifest patch requires object roots")
    after = deep_merge(before, overlay)
    if not dry_run:
        dump_json(after, str(path))
    return {
        "manifest": manifest_id,
        "path": str(path),
        "dry_run": dry_run,
        "before": before,
        "after": after,
    }
