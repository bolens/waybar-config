"""Generate / validate / check / restart subprocess helpers."""

from __future__ import annotations

import os
import shutil
import subprocess
from typing import Any

from paths import CHECK_SUBSETS, WaybarPaths
from protocol import log

DEFAULT_TIMEOUT = 180
LONG_TIMEOUT = 300

MAKE_TARGETS = {
    "syntax": "check-syntax",
    "python": "check-python",
    "validate": "validate",
    "fast": "check-fast",
    "contracts": "check-contracts",
    "ruff": "check-ruff",
}


def _test_suite() -> bool:
    return bool(os.environ.get("TEST_SUITE_RUN"))


def _mock_bin() -> str:
    return os.environ.get("MOCK_BIN", "")


def run_cmd(
    args: list[str],
    *,
    cwd: str | None = None,
    env: dict[str, str] | None = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> dict[str, Any]:
    """Run a command, respecting TEST_SUITE_RUN / MOCK_BIN like millenium-mcp."""
    cmd_args = list(args)
    log(f"Executing: {' '.join(cmd_args)}")

    if _test_suite():
        # CI/agent runs: never touch real systemctl/make. Prefer a MOCK_BIN stub
        # when present so success paths are exercised without host side effects.
        mock_bin = _mock_bin()
        stub = os.path.join(mock_bin, os.path.basename(args[0])) if mock_bin else ""
        if stub and os.path.isfile(stub) and os.access(stub, os.X_OK):
            try:
                res = subprocess.run(
                    [stub] + args[1:],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=timeout,
                    cwd=cwd,
                    env=env,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                return {
                    "ok": False,
                    "output": f"Error: timed out after {timeout}s: {' '.join(args)}",
                    "returncode": -1,
                }
            combined = (res.stdout or "") + (
                f"\n{res.stderr}" if res.stderr else ""
            )
            return {
                "ok": res.returncode == 0,
                "output": combined.strip()
                or f"Command finished with exit code {res.returncode}",
                "returncode": res.returncode,
            }
        log("[TEST] Skipping host execution to protect system state")
        return {
            "ok": True,
            "output": "[TEST] Skipped host execution",
            "returncode": 0,
            "skipped": True,
        }

    try:
        res = subprocess.run(
            cmd_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            cwd=cwd,
            env=env,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "output": f"Error: timed out after {timeout}s: {' '.join(args)}",
            "returncode": -1,
        }
    except OSError as exc:
        return {"ok": False, "output": f"Execution error: {exc}", "returncode": -1}

    combined = (res.stdout or "") + (f"\n{res.stderr}" if res.stderr else "")
    return {
        "ok": res.returncode == 0,
        "output": combined.strip()
        or f"Command finished with exit code {res.returncode}",
        "returncode": res.returncode,
    }


def _env_for(paths: WaybarPaths) -> dict[str, str]:
    env = os.environ.copy()
    env["WAYBAR_HOME"] = str(paths.home)
    env["WAYBAR_SCRIPTS"] = str(paths.scripts_dir)
    return env


def generate(paths: WaybarPaths) -> dict[str, Any]:
    make = shutil.which("make") or "make"
    return run_cmd(
        [make, "-C", str(paths.home), "generate"],
        cwd=str(paths.home),
        env=_env_for(paths),
        timeout=LONG_TIMEOUT,
    )


def validate(paths: WaybarPaths) -> dict[str, Any]:
    script = paths.scripts_dir / "ci" / "validate-generated-config.sh"
    return run_cmd(
        ["bash", str(script)],
        cwd=str(paths.home),
        env=_env_for(paths),
        timeout=DEFAULT_TIMEOUT,
    )


def check_drift(paths: WaybarPaths) -> dict[str, Any]:
    script = paths.scripts_dir / "ci" / "check-generated-drift.sh"
    return run_cmd(
        ["bash", str(script)],
        cwd=str(paths.home),
        env=_env_for(paths),
        timeout=LONG_TIMEOUT,
    )


def check(paths: WaybarPaths, subset: str) -> dict[str, Any]:
    if subset not in CHECK_SUBSETS:
        raise ValueError(
            f"invalid check subset '{subset}'. "
            f"Must be one of: {', '.join(sorted(CHECK_SUBSETS))}"
        )
    target = MAKE_TARGETS[subset]
    make = shutil.which("make") or "make"
    return run_cmd(
        [make, "-C", str(paths.home), target],
        cwd=str(paths.home),
        env=_env_for(paths),
        timeout=LONG_TIMEOUT,
    )


def status(paths: WaybarPaths) -> dict[str, Any]:
    out: dict[str, Any] = {"waybar_home": str(paths.home)}
    systemctl = shutil.which("systemctl")
    if systemctl:
        for unit in ("waybar.service", "waybar-healthcheck.timer"):
            res = run_cmd(
                [systemctl, "--user", "is-active", unit],
                timeout=15,
            )
            # Under TEST_SUITE_RUN this may skip; still report.
            out[unit] = res.get("output", "")
    else:
        out["systemctl"] = "not found"
    # Lightweight process probe (read-only).
    try:
        res = subprocess.run(
            ["pgrep", "-a", "waybar"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            check=False,
        )
        out["pgrep"] = (res.stdout or "").strip() or "(none)"
    except (OSError, subprocess.TimeoutExpired):
        out["pgrep"] = "unavailable"
    return out


def restart(*, confirm: bool = False) -> dict[str, Any]:
    if not confirm:
        return {
            "ok": False,
            "output": "Error: waybar_restart requires confirm=true",
            "returncode": 1,
        }
    systemctl = shutil.which("systemctl") or "systemctl"
    return run_cmd(
        [systemctl, "--user", "restart", "waybar.service"],
        timeout=60,
    )
