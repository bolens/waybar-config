"""Git hook environments must not redirect a fixture into its caller's repository."""
import os
import json
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys


ROOT = Path(__file__).resolve().parents[1]


class GitFixtureIsolationTests(unittest.TestCase):
    def test_generated_drift_does_not_use_parent_appicon_or_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            source = parent / "source"
            source.mkdir()
            files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
            for name in files:
                if not name:
                    continue
                relative = Path(os.fsdecode(name))
                target = source / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / relative, target, follow_symlinks=False)
            home = parent / "parent-home"
            cache = parent / "parent-cache"
            home.mkdir()
            cache.mkdir()
            sentinel = cache / "sentinel"
            sentinel.write_text("parent cache\n")
            calls = cache / "unexpected-appicon"
            tool = parent / "appicon"
            tool.write_text(f"#!/bin/sh\nprintf 'called\\n' >> '{calls}'\nexit 1\n")
            tool.chmod(0o755)
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith("GIT_")}
            environment.update(HOME=str(home), XDG_CACHE_HOME=str(cache), APPICON_BIN=str(tool),
                               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
            def git(*arguments):
                subprocess.run(["git", *arguments], cwd=source, env=environment,
                               check=True, capture_output=True, timeout=15)
            git("init", "--quiet", "--initial-branch=main")
            git("config", "core.hooksPath", os.devnull)
            git("config", "user.name", "Drift fixture")
            git("config", "user.email", "fixture@example.invalid")
            git("add", ".")
            git("commit", "--quiet", "-m", "fixture source")
            result = subprocess.run(["bash", "scripts/ci/check-generated-drift.sh"],
                                    cwd=source, env=environment, text=True,
                                    capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(calls.exists(), "drift check executed the parent's appicon")
            self.assertEqual(list(cache.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_text(), "parent cache\n")
            self.assertEqual(list(home.iterdir()), [])

    def test_generator_owns_user_state_and_appicon_selection(self):
        for explicit_fixture in (False, True):
            with self.subTest(explicit_fixture=explicit_fixture), tempfile.TemporaryDirectory() as directory:
                parent = Path(directory)
                home = parent / "parent-home"
                cache = parent / "parent-cache"
                binary = home / ".local/bin"
                binary.mkdir(parents=True)
                cache.mkdir()
                sentinel = cache / "sentinel"
                sentinel.write_text("parent cache must remain unchanged\n")
                host_calls = cache / "unexpected-appicon"
                host = binary / "appicon"
                host.write_text(f"#!/bin/sh\nprintf 'called\\n' >> '{host_calls}'\nexit 1\n")
                host.chmod(0o755)
                fixture = parent / "fixture-appicon"
                fixture.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$XDG_CACHE_HOME/appicon-calls"\nexit 1\n')
                fixture.chmod(0o755)
                baseline = {str(path.relative_to(parent)): path.read_bytes()
                            for tree in (home, cache) for path in tree.rglob("*") if path.is_file()}
                state = parent / "state.json"
                environment = {key: value for key, value in os.environ.items()
                               if not key.startswith("GIT_")}
                environment.update(HOME=str(home), XDG_CACHE_HOME=str(cache),
                                   XDG_CONFIG_HOME=str(home / "config"),
                                   XDG_DATA_HOME=str(home / "data"),
                                   XDG_STATE_HOME=str(home / "state"),
                                   XDG_RUNTIME_DIR=str(home / "runtime"),
                                   TEST_DIR=str(home), WAYBAR_TEST_EXTRA_CLEANUP=str(cache),
                                   APPICON_BIN=str(host), PATH=str(binary) + os.pathsep + environment["PATH"],
                                   FIXTURE_PYTHON=sys.executable, FIXTURE_STATE=str(state),
                                   FIXTURE_APPICON=str(fixture), FIXTURE_EXPLICIT=str(int(explicit_fixture)))
                script = r'''
set -euo pipefail
ROOT_DIR=$PWD
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin parent-state-isolation
waybar_test_gen_sandbox
if [[ "$FIXTURE_EXPLICIT" == 1 ]]; then export APPICON_BIN="$FIXTURE_APPICON"; fi
waybar_test_gen_default
export SUITE_RUNTIME
"$FIXTURE_PYTHON" - <<'PY'
import json, os
from pathlib import Path
keys = ['HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME',
        'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'TMPDIR']
paths = {key: os.environ.get(key) for key in keys}
calls = Path(os.environ['XDG_CACHE_HOME']) / 'appicon-calls'
Path(os.environ['FIXTURE_STATE']).write_text(json.dumps({
    'paths': paths, 'suite': os.environ['SUITE_RUNTIME'],
    'directories_exist': all(value and Path(value).is_dir() for value in paths.values()),
    'fixture_calls': calls.read_text().splitlines() if calls.exists() else [],
}))
PY
waybar_test_end
'''
                result = subprocess.run(["bash", "-c", script], cwd=ROOT, env=environment,
                                        text=True, capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                observed = json.loads(state.read_text())
                suite = Path(observed["suite"])
                self.assertTrue(observed["directories_exist"])
                for key, value in observed["paths"].items():
                    self.assertTrue(Path(value).is_relative_to(suite), (key, value))
                self.assertFalse(suite.exists(), "suite state was not cleaned on exit")
                self.assertEqual(bool(observed["fixture_calls"]), explicit_fixture)
                if explicit_fixture:
                    self.assertIn("prefetch", observed["fixture_calls"])
                    self.assertIn("resolve", observed["fixture_calls"])
                self.assertFalse(host_calls.exists(), "generator executed the parent's appicon")
                after = {str(path.relative_to(parent)): path.read_bytes()
                         for tree in (home, cache) for path in tree.rglob("*") if path.is_file()}
                self.assertEqual(after, baseline)

    def test_real_fixture_preserves_calling_repository(self):
        for full_context in (False, True):
            with self.subTest(full_context=full_context), tempfile.TemporaryDirectory() as directory:
                outer = Path(directory) / "outer"
                outer.mkdir()
                environment = {key: value for key, value in os.environ.items()
                               if not key.startswith("GIT_")}
                environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
                physical_tmp = Path(directory) / "physical-tmp"
                physical_tmp.mkdir()
                alias_tmp = Path(directory) / "alias-tmp"
                alias_tmp.symlink_to(physical_tmp, target_is_directory=True)
                environment["TMPDIR"] = str(alias_tmp)

                def git(*arguments):
                    return subprocess.check_output(["git", *arguments], cwd=outer,
                                                   env=environment, text=True, timeout=15).strip()

                git("init", "--quiet", "--initial-branch=main")
                git("config", "user.name", "Fixture caller")
                git("config", "user.email", "caller@example.invalid")
                (outer / "data").mkdir()
                settings = outer / "data/waybar-settings.jsonc"
                settings.write_text('{"caller": true}\n')
                git("add", "--", "data/waybar-settings.jsonc")
                git("commit", "--quiet", "-m", "caller baseline")
                paths = [outer / ".git/index", outer / ".git/config", settings]
                baseline = [path.read_bytes() for path in paths]
                head = git("rev-parse", "HEAD")
                hook_environment = {**environment, "GIT_DIR": str(outer / ".git")}
                if full_context:
                    hook_environment.update(GIT_WORK_TREE=str(outer),
                                            GIT_INDEX_FILE=str(outer / ".git/index"),
                                            GIT_COMMON_DIR=str(outer / ".git"),
                                            GIT_OBJECT_DIRECTORY=str(outer / ".git/objects"))
                result = subprocess.run(["bash", str(ROOT / "scripts/ci/tests/secrets/precommit-secrets.sh")],
                                        cwd=ROOT, env=hook_environment, text=True,
                                        capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(git("rev-parse", "HEAD"), head)
                self.assertEqual(git("symbolic-ref", "HEAD"), "refs/heads/main")
                self.assertEqual([path.read_bytes() for path in paths], baseline)
                self.assertEqual(git("status", "--porcelain"), "")


    def test_wrong_fixture_root_stops_before_identity_or_index_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "bin"
            binary.mkdir()
            writes = root / "writes"
            probes = root / "probes"
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)
            wrapper = binary / "git"
            wrapper.write_text(
                "#!/usr/bin/env python3\n"
                "import os, sys\n"
                "args = sys.argv[1:]\n"
                "if args == ['rev-parse', '--show-toplevel']:\n"
                f" with open({str(probes)!r}, 'w') as output: output.write('wrong-root\\n')\n"
                " print('/not-the-owned-fixture'); sys.exit(0)\n"
                "if args and args[0] in {'config', 'add', 'commit', 'reset'}:\n"
                f" with open({str(writes)!r}, 'a') as output: output.write(args[0] + '\\n')\n"
                f"os.execv({real_git!r}, [{real_git!r}] + args)\n"
            )
            wrapper.chmod(0o755)
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith("GIT_")}
            environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
            caller = root / "caller"
            caller.mkdir()
            def git(*arguments):
                return subprocess.check_output([real_git, *arguments], cwd=caller,
                                               env=environment, text=True, timeout=15).strip()
            git("init", "--quiet", "--initial-branch=main")
            git("config", "core.hooksPath", os.devnull)
            git("config", "user.name", "Fixture caller")
            git("config", "user.email", "caller@example.invalid")
            sentinel = caller / "sentinel"
            sentinel.write_text("caller data\n")
            git("add", "sentinel")
            git("commit", "--quiet", "-m", "caller baseline")
            paths = [caller / ".git/config", caller / ".git/index", sentinel]
            baseline = [path.read_bytes() for path in paths]
            head = git("rev-parse", "HEAD")
            branch = git("symbolic-ref", "HEAD")
            hook_environment = {**environment, "GIT_DIR": str(caller / ".git"),
                                "GIT_WORK_TREE": str(caller),
                                "GIT_INDEX_FILE": str(caller / ".git/index")}
            hook_environment["PATH"] = str(binary) + os.pathsep + environment["PATH"]
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/ci/tests/secrets/precommit-secrets.sh")],
                cwd=ROOT, env=hook_environment, text=True, capture_output=True, timeout=60,
            )
            self.assertEqual(probes.read_text(), "wrong-root\n")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(writes.exists(), "fixture wrote Git identity/index after wrong-root denial")
            self.assertEqual(git("rev-parse", "HEAD"), head)
            self.assertEqual(git("symbolic-ref", "HEAD"), branch)
            self.assertEqual([path.read_bytes() for path in paths], baseline)
            self.assertEqual(git("status", "--porcelain"), "")


if __name__ == "__main__":
    unittest.main()
