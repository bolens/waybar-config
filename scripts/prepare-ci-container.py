#!/usr/bin/env python3
"""Provide minimal-PATH fixture tools only inside the disposable root CI container."""

from pathlib import Path
import os


def install_links(search_path, destination, store_root=Path("/nix/store")):
    """Link executable Nix tools without replacing existing container tools."""
    seen = set()
    for value in search_path.split(os.pathsep):
        directory = Path(value)
        if not directory.is_dir() or not directory.resolve().is_relative_to(
            store_root.resolve()
        ):
            continue
        for tool in sorted(directory.iterdir()):
            target = tool.resolve()
            if (
                tool.name in seen
                or not target.is_file()
                or not os.access(target, os.X_OK)
                or not target.is_relative_to(store_root.resolve())
            ):
                continue
            seen.add(tool.name)
            link = destination / tool.name
            if not link.exists() and not link.is_symlink():
                link.symlink_to(target)


def main():
    if (
        os.environ.get("CI") not in {"true", "woodpecker"}
        or os.geteuid() != 0
        or not Path("/.dockerenv").is_file()
    ):
        raise SystemExit(
            "container preparation requires root in the disposable CI Docker container"
        )
    destination = Path("/usr/bin")
    install_links(os.environ["PATH"], destination)
    required = ["bash", "sed", "jq", "python3"]
    if any(not os.access(destination / name, os.X_OK) for name in required):
        raise SystemExit(
            "required minimal-PATH fixture tools were not supplied by the development shell"
        )


if __name__ == "__main__":
    main()
