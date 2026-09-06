# Plan: Generated Waybar settings and module adapters

The [specification](spec.md) preserves existing behavior. Use the project guide
and constitution for implementation constraints. Keep upstream-managed templates,
helpers, and integration manifests unchanged.

## Source ownership

- `data/waybar-settings.jsonc`
- `scripts/generate`
- `scripts/lib`
- `scripts/mcp`
- `scripts/services/coolercontrol`
- `scripts/ci/tests`
- `modules`
- `Makefile`

## Constitution check

Keep the repository constitution, authoritative source files, existing interfaces, and native validation. The baseline does not authorize live host mutation, publication of private data, or changes to managed Spec Kit files.

## Validation

```sh
pnpm install --frozen-lockfile
make check
```

Run checks in an isolated checkout. Commands are instructions, not evidence of
a pass. Record results in `coverage.md`, keep incomplete work in `tasks.md`, and
follow `RELEASING.md` for reviewed delivery. No live operation is required solely
to create this retrospective baseline.
