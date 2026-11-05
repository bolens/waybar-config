# Complete portable Woodpecker validation

## Requirements

- Every push, pull request, and manual pipeline runs the complete native Linux
  repository gate and pinned fleet Spec Kit validation without changed-path skips.
- GitHub and Gitea executions test their own exact source revision. Existing
  `woodpecker` workflow identity remains available for protected-check migration.
- Tools come from the existing committed Nix/devenv lock; the container and
  bootstrap revision are immutable. The disposable container owns its writable
  store, has no Docker socket or host Nix daemon, and needs no privileged mode.
- Native macOS and actual Docker/devcontainer builds remain on GitHub Actions.
  GitHub metadata automation and the trusted Spec Kit updater remain separate.
- Existing Actions and protections remain until current-head native success and
  a separately verified protected-check cutover. No publication credentials,
  registry writes, or application/firewall/desktop operations are introduced.

## Acceptance

Prove workflow syntax, native commands, full-history scanning where applicable,
locked tool setup, private-fixture isolation, and the real constrained container
runtime. Record cold-start time, storage, and timeout limitations. Passing local
checks does not establish native forge status or protection migration.
