# Validation

Run from the repository root with the normal local test dependencies available:

```sh
bash scripts/ci/tests/generator/coolercontrol-module-auth.sh
bash scripts/ci/tests/secrets/coolercontrol-sync-auth.sh
make generate
make check
```

The authentication suite uses disposable credentials and transport doubles.
Expect token preference, fallback, credential exposure, cleanup, and cache checks
to pass. An isolated loopback server verifies actual curl Basic authentication
from stdin without contacting CoolerControl. Review any generated diff and run
required hosted CI and CodeQL on the final candidate.

## Evidence

- Strengthened stdin-only mock failed against the original file-based helper.
- Real curl validates API, dump, and sync login; API tests cover cookie reuse,
  rejected login, rejected status, timeout, and session-directory cleanup.
- A separate isolated shell diagnostic fixture verifies successful and rejected
  login, cookies, absence of password files, and cleanup.
- Both existing auth suites pass. Two independent reviews found no transport
  regressions; their generated-output and test-assertion feedback was addressed.
- Fast gates, secrets suites, Ruff, shfmt, CSS/Markdown lint, secret scan, and
  canonical generated-drift checks pass. GTK runtime probing is unavailable
  locally because PyGObject GTK3 is absent.
- Loopback tests require socket permission; the sandboxed full-gate invocation
  cannot create that fixture. The focused suite passes with socket permission.

No tagged release or live Waybar restart is part of this repository delivery.
