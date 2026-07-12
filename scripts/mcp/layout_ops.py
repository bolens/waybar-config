"""Groups, layouts, bars, intervals, and signals helpers."""

from __future__ import annotations

from typing import Any

from paths import LAYOUT_BARS, LAYOUT_SIDES, WaybarPaths
from settings_ops import load_settings, write_settings


def list_groups(paths: WaybarPaths) -> dict[str, Any]:
    data = load_settings(paths)
    groups = data.get("groups") if isinstance(data.get("groups"), dict) else {}
    return {
        name: {
            "drawer": block.get("drawer") if isinstance(block, dict) else None,
            "modules": block.get("modules") if isinstance(block, dict) else None,
        }
        for name, block in groups.items()
    }


def get_group(paths: WaybarPaths, name: str) -> dict[str, Any]:
    groups = list_groups(paths)
    if name not in groups:
        raise KeyError(f"unknown group: {name}")
    return {"name": name, **groups[name]}


def set_group_modules(
    paths: WaybarPaths, name: str, modules: list[Any]
) -> dict[str, Any]:
    if not isinstance(modules, list) or not all(isinstance(m, str) for m in modules):
        raise ValueError("modules must be an array of strings")
    data = load_settings(paths)
    groups = data.get("groups")
    if not isinstance(groups, dict) or name not in groups:
        raise KeyError(f"unknown group: {name}")
    block = groups[name]
    if not isinstance(block, dict):
        block = {}
        groups[name] = block
    block["modules"] = modules
    write_settings(paths, data)
    return get_group(paths, name)


def get_layout(paths: WaybarPaths, bar: str | None = None) -> Any:
    data = load_settings(paths)
    layouts = data.get("layouts") if isinstance(data.get("layouts"), dict) else {}
    if bar is None:
        return layouts
    if bar not in LAYOUT_BARS:
        raise ValueError(
            f"invalid bar '{bar}'. Must be one of: {', '.join(sorted(LAYOUT_BARS))}"
        )
    if bar not in layouts:
        raise KeyError(f"layout not found: {bar}")
    return layouts[bar]


def set_layout_modules(
    paths: WaybarPaths,
    bar: str,
    side: str,
    modules: list[Any],
) -> dict[str, Any]:
    if bar not in LAYOUT_BARS:
        raise ValueError(
            f"invalid bar '{bar}'. Must be one of: {', '.join(sorted(LAYOUT_BARS))}"
        )
    if side not in LAYOUT_SIDES:
        raise ValueError(
            f"invalid side '{side}'. Must be one of: {', '.join(sorted(LAYOUT_SIDES))}"
        )
    if not isinstance(modules, list) or not all(isinstance(m, str) for m in modules):
        raise ValueError("modules must be an array of strings")
    data = load_settings(paths)
    layouts = data.get("layouts")
    if not isinstance(layouts, dict):
        layouts = {}
        data["layouts"] = layouts
    block = layouts.get(bar)
    if not isinstance(block, dict):
        block = {}
        layouts[bar] = block
    block[side] = modules
    write_settings(paths, data)
    return {"bar": bar, "side": side, "modules": modules}


def get_bars(paths: WaybarPaths) -> Any:
    data = load_settings(paths)
    return data.get("bars", {})


def set_bars(paths: WaybarPaths, patch: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(patch, dict):
        raise ValueError("patch must be an object")
    data = load_settings(paths)
    bars = data.get("bars")
    if not isinstance(bars, dict):
        bars = {}
        data["bars"] = bars
    bars.update(patch)
    write_settings(paths, data)
    return {"bars": bars}


def get_intervals(paths: WaybarPaths) -> Any:
    return load_settings(paths).get("module_intervals", {})


def set_interval(paths: WaybarPaths, key: str, value: Any) -> dict[str, Any]:
    if not isinstance(key, str) or not key:
        raise ValueError("key must be a non-empty string")
    if not (value == "once" or isinstance(value, int)):
        raise ValueError("value must be 'once' or an integer")
    data = load_settings(paths)
    intervals = data.get("module_intervals")
    if not isinstance(intervals, dict):
        intervals = {}
        data["module_intervals"] = intervals
    intervals[key] = value
    write_settings(paths, data)
    return {"key": key, "value": value}


def get_signals(paths: WaybarPaths) -> Any:
    return load_settings(paths).get("signals", {})


def set_signal(paths: WaybarPaths, key: str, value: Any) -> dict[str, Any]:
    if not isinstance(key, str) or not key:
        raise ValueError("key must be a non-empty string")
    if not isinstance(value, int):
        raise ValueError("signal value must be an integer")
    data = load_settings(paths)
    signals = data.get("signals")
    if not isinstance(signals, dict):
        signals = {}
        data["signals"] = signals
    signals[key] = value
    write_settings(paths, data)
    return {"key": key, "value": value}
