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
