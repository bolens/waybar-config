"""Git hook environments must not redirect a fixture into its caller's repository."""
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class GitFixtureIsolationTests(unittest.TestCase):
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
