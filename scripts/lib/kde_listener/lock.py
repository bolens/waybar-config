import atexit
import os
import shutil
import sys


def acquire_lock(lock_name):
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock_dir = os.path.join(runtime_dir, f"waybar-dock-listener-{lock_name}.lock.d")
    lock_pid_file = os.path.join(lock_dir, "pid")

    try:
        os.makedirs(lock_dir, exist_ok=False)
    except FileExistsError:
        if os.path.exists(lock_pid_file):
            try:
                with open(lock_pid_file, "r") as f:
                    old_pid = int(f.read().strip())
                os.kill(old_pid, 0)
                sys.exit(0)
            except (ValueError, OSError):
                pass
        shutil.rmtree(lock_dir, ignore_errors=True)
        try:
            os.makedirs(lock_dir, exist_ok=False)
        except Exception:
            sys.exit(0)

    with open(lock_pid_file, "w") as f:
        f.write(str(os.getpid()))

    def cleanup_lock():
        try:
            os.remove(lock_pid_file)
            os.rmdir(lock_dir)
        except Exception:
            pass

    atexit.register(cleanup_lock)
