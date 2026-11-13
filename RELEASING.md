# Delivery playbook

[Documentation](docs/README.md)

Waybar Config continuously delivers declarative source and generated artifacts
from protected `main`; it has no tagged releases. Restarting or replacing a live
Waybar configuration is a separate authorized operation.

## Prepare and validate

Branch from current `origin/main`. Change `data/waybar-settings.jsonc` or the
appropriate generator source, never generated outputs directly. Keep secrets
in the ignored overlay.

```sh
make generate
make check
```

Review intended generated diffs, documentation-index changes, optional-module
fallback behavior, and CI/path-filter coverage.

## Push

Follow the [fleet push and merge steps](https://github.com/bolens/.github/blob/main/RELEASING.md#push-and-merge).
After the local checks pass, inspect the diff, commit focused changes, and push
only the feature branch to the GitHub remote:

```sh
git push --set-upstream origin HEAD
```

Confirm `origin` points to `bolens/waybar-config` on GitHub before pushing.
Do not push `main`, force-push, skip failing hooks, or bypass protection.

## Review, deliver, and verify

Require a pull request, all checks, resolved conversations, and a squash merge.
Confirm the merge SHA passes CI and a clean regeneration produces no drift. Do
not restart the live bar during repository delivery.

## Recover

Correct source through another PR. For an authorized live rollout, preserve
the current config and CSS, validate in an isolated Waybar process when
possible, and restore the prior generated set if startup, layout, modules, or
secrets handling regresses.

Fleet policy: <https://github.com/bolens/.github/blob/main/RELEASING.md>.

## Woodpecker migration

GitHub Actions remain active until Woodpecker has passed the current PR revision
and the maintainer has verified the new required status on the correct forge.
The existing `woodpecker` workflow identity is preserved. Read back protections
before retiring duplicate checks; keep native macOS and actual Docker builds,
plus metadata/update automation, until their own replacements are verified.
Neither a green pipeline nor this migration authorizes applying live state or
creating publication credentials.

The default-off repository variable `WOODPECKER_LINUX_CI` retires duplicate
portable Linux checks only after the maintainer verifies exact PR and merged-main
native results, migrates required checks and runs the actual weekly native cron.
Configure one `main` full-validation cron for Monday 06:17 UTC, consolidating the
previous weekly CI and Gitleaks scans. Preserve the hosted schedules until that
cron passes; then enable the flag. Native macOS, actual Docker/devcontainer checks,
assignment and the Spec Kit updater remain hosted. Remove or set the flag false
to restore duplicate hosted validation without changing source.

## Managed integration validation

`bash scripts/ci/check-spec-kit.sh` runs the reviewed public fleet validator at
`c161a6757130ea687def9eb1e81c6a4190488f07` against the current managed manifests.
It checks the downloaded script's SHA-256 before execution, rejects redirects,
limits the download to 64 KiB and 60 seconds, and bounds validation to four
minutes. Local reproduction requires Bash and Python 3 on Linux/macOS with HTTPS
access. Temporary supplier files are removed. No secret or installed skill link
is required.

The repository maintainer reviews this direct pin during monthly dependency
maintenance and whenever the shared validator receives a security fix. Review
the immutable commit and checksum together, then require actual native PR and
merged-main validation. Existing dependency automation does not monitor this
embedded pin. The existing native check identity and mixed GitHub Spec Kit
workflow/updater configuration are preserved.

`scripts/check-spec-kit.sh` remains a compatibility entrypoint to the same
canonical CI helper. The existing locked native development-shell command keeps
its path and workflow identity. No live Waybar state is applied.
