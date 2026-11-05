# Complete portable Woodpecker validation

## Requirements

- Every main push, pull request, manual pipeline and configured main cron runs
  the complete native Linux
  repository gate and pinned fleet Spec Kit validation without changed-path skips.
- GitHub and Gitea executions test their own exact source revision. Existing
  `woodpecker` workflow identity remains available for protected-check migration.
- Tools come from the existing committed Nix/devenv lock; the container and
  bootstrap revision are immutable. The disposable container owns its writable
  store, has no Docker socket or host Nix daemon, and needs no privileged mode.
- Native macOS and actual Docker/devcontainer builds remain on GitHub Actions.
  GitHub metadata automation and the trusted Spec Kit updater remain separate.
- Existing Actions remain active by default. Duplicate Linux checks retire only
  after exact PR/main native success, required-check migration and an actual
  Monday 06:17 UTC main cron proof, using `WOODPECKER_LINUX_CI=true`.
  Native macOS, Docker/devcontainer and metadata/update automation remain.
  No publication credentials,
  registry writes, or application/firewall/desktop operations are introduced.

## Acceptance

Prove workflow syntax, native commands, full-history scanning where applicable,
locked tool setup, private-fixture isolation, and the real constrained container
runtime. Record cold-start time, storage, and timeout limitations. Passing local
checks does not establish native forge status or protection migration.
