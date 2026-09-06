# Implementation Plan: CoolerControl password handoff

**Branch**: `001-coolercontrol-password-stdin` | **Date**: 2026-09-06

**Spec**: [spec.md](spec.md)

## Summary

Pass the existing netrc payload through a subprocess pipe. Curl reads it from
`/dev/stdin`; the helper no longer creates a netrc file. Preserve host matching,
bearer authentication, cookie state, timeouts, and error results.

## Technical Context

- Language: Python 3, standard library, existing Bash test harness.
- Dependencies: existing curl executable and Linux `/dev/stdin`.
- Storage: existing private session cookies only; no password file.
- Testing: extend the existing `coolercontrol-module-auth` suite and use an
  isolated local HTTP fixture to verify real curl stdin authentication.
- Scope: API, dump, authentication check, and password sync helpers, with existing authentication suites.
- Performance: no additional child process or network request.

## Constitution Check

Passed before and after design: no live secret files or services are touched;
settings and generated sources retain their ownership; optional authentication
failure remains nonfatal; coverage stays in an already-selected suite.

## Project Structure

- `scripts/services/coolercontrol/coolercontrol-api.py`: subprocess and login flow.
- `scripts/ci/tests/generator/coolercontrol-module-auth.sh`: regression coverage.
- `specs/001-coolercontrol-password-stdin/`: decisions and validation evidence.

No public CLI or settings interface changes. No new generated artifacts expected.
