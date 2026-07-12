"""Theme list/get/set/write helpers."""

from __future__ import annotations

from typing import Any

from jsonc_util import dump_json, load_jsonc
from paths import THEME_MODES, WaybarPaths, ensure_safe_name
from settings_ops import load_settings, write_settings


def list_themes(paths: WaybarPaths) -> dict[str, Any]:
    names: list[str] = []
    if paths.themes_dir.is_dir():
        names = sorted(p.stem for p in paths.themes_dir.glob("*.jsonc"))
    settings = load_settings(paths)
    theme = settings.get("theme") if isinstance(settings.get("theme"), dict) else {}
    return {
        "themes": names,
        "active": {
            "mode": theme.get("mode"),
            "preset": theme.get("preset"),
        },
    }


def get_theme(paths: WaybarPaths, name: str) -> Any:
    path = paths.theme_file(name)
    if not path.is_file():
        raise FileNotFoundError(f"theme not found: {name}")
    return load_jsonc(str(path))


def set_theme(
    paths: WaybarPaths,
    *,
    mode: str | None = None,
    preset: str | None = None,
    wallpaper: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = load_settings(paths)
    theme = data.get("theme")
    if not isinstance(theme, dict):
        theme = {}
        data["theme"] = theme
    if mode is not None:
        if mode not in THEME_MODES:
            raise ValueError(
                f"invalid mode '{mode}'. Must be one of: {', '.join(sorted(THEME_MODES))}"
            )
        theme["mode"] = mode
    if preset is not None:
        ensure_safe_name(preset, "theme")
        theme_path = paths.theme_file(preset)
        if not theme_path.is_file():
            raise FileNotFoundError(f"theme preset not found: {preset}")
        theme["preset"] = preset
    if wallpaper is not None:
        if not isinstance(wallpaper, dict):
            raise ValueError("wallpaper must be an object")
        existing = theme.get("wallpaper")
        if not isinstance(existing, dict):
            existing = {}
        existing.update(wallpaper)
        theme["wallpaper"] = existing
    write_settings(paths, data)
    return {"theme": theme}


def apply_preset(
    paths: WaybarPaths,
    name: str,
    *,
    keep_preset_mode: bool = False,
) -> dict[str, Any]:
    preset = get_theme(paths, name)
    data = load_settings(paths)
    theme = data.get("theme")
    if not isinstance(theme, dict):
        theme = {}
        data["theme"] = theme
    colors = preset.get("colors") if isinstance(preset, dict) else None
    if isinstance(colors, dict):
        theme["colors"] = colors
    # Copy common non-color keys when present on the preset.
    for key in (
        "font_family",
        "font_size",
        "tooltip_font_size",
        "border_radius",
        "tooltip_padding",
    ):
        if isinstance(preset, dict) and key in preset:
            theme[key] = preset[key]
    theme["preset"] = name
    theme["mode"] = "preset" if keep_preset_mode else "static"
    write_settings(paths, data)
    return {"theme": theme, "applied_from": name}


def write_theme(
    paths: WaybarPaths,
    name: str,
    body: dict[str, Any],
    *,
    confirm_overwrite: bool = False,
) -> dict[str, Any]:
    ensure_safe_name(name, "theme")
    path = paths.theme_file(name)
    paths.themes_dir.mkdir(parents=True, exist_ok=True)
    if path.is_file() and not confirm_overwrite:
        raise ValueError(
            f"theme '{name}' exists; pass confirm_overwrite=true to replace"
        )
    if not isinstance(body, dict):
        raise ValueError("theme body must be an object")
    dump_json(body, str(path))
    return {"path": str(path), "name": name}
