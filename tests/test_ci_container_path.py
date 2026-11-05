"""Container-only Nix tool links: ownership, precedence and host refusal."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "prepare", Path(__file__).resolve().parents[1] / "scripts/prepare-ci-container.py"
)
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class ContainerPathTests(unittest.TestCase):
    def test_links_only_executable_store_tools_and_preserves_existing_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "canonical").mkdir()
            (directory / "alias").symlink_to(directory / "canonical", target_is_directory=True)
            root = directory / "alias"
            store = root / "store"
            first, second, outside, destination = [
                root / name
                for name in [
                    "store/first/bin",
                    "store/second/bin",
                    "outside",
                    "usr/bin",
                ]
            ]
            for directory in [first, second, outside, destination]:
                directory.mkdir(parents=True)
            for directory, name in [
                (first, "bash"),
                (second, "bash"),
                (second, "jq"),
                (outside, "unsafe"),
            ]:
                tool = directory / name
                tool.write_text("#!/bin/sh\n")
                tool.chmod(0o755)
            (first / "data").write_text("not executable")
            (first / "escape").symlink_to(outside / "unsafe")
            (destination / "env").write_text("preserve base container tool")
            path = os.pathsep.join(map(str, [first, second, outside]))
            prepare.install_links(path, destination, store)
            self.assertEqual((destination / "bash").resolve(), (first / "bash").resolve())
            self.assertEqual((destination / "jq").resolve(), (second / "jq").resolve())
            self.assertEqual(
                (destination / "env").read_text(), "preserve base container tool"
            )
            self.assertFalse((destination / "unsafe").exists())
            self.assertFalse((destination / "escape").exists())
            self.assertFalse((destination / "data").exists())
            prepare.install_links(path, destination, store)
            self.assertEqual((destination / "bash").resolve(), (first / "bash").resolve())

    def test_refuses_host_before_linking(self):
        with (
            patch.dict(os.environ, {"CI": ""}),
            patch.object(prepare, "install_links") as install,
            self.assertRaises(SystemExit),
        ):
            prepare.main()
        install.assert_not_called()


if __name__ == "__main__":
    unittest.main()
