"""Git hook environments must not redirect a fixture into its caller's repository."""
import os
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


if __name__ == "__main__":
    unittest.main()
