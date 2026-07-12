# Adding a module

> Doc map: [Documentation index](README.md) · [Architecture](architecture.md) · [Settings reference](settings-reference.md) · [Scripts layout](../scripts/README.md)

Checklist for a new Waybar status (or click) module in this tree.

## 1. Pick a domain folder

Put scripts under the matching folder (see [`scripts/README.md`](../scripts/README.md)):

| Kind | Folder examples |
|------|-----------------|
| System metrics | `scripts/system/` |
| Network / VPN | `scripts/network/` |
| Media | `scripts/media/` |
| Third-party service | `scripts/services/<concern>/` |
| Shared helpers | `scripts/lib/` |
| Codegen | `scripts/generate/` |

Growth rule: if a domain exceeds ~20 files, split further (as with `services/`).

## 2. Write the status script

Typical pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
# Optional: . "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"

module_key="my_feature"   # must match module_intervals / signals keys
cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/${module_key}.json"
lock_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/${module_key}.lock"
ttl="$(waybar_module_interval "$module_key" 60)"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" 30; then
    exit 0
  fi
  emit_waybar_json "…" "Initializing…" "normal"
  exit 0
fi

# --refresh: gather data, then emit_waybar_json / write cache
```

Notes:

- Prefer hiding when deps are missing (Waybar `disconnected` / empty output) rather than error spam.
- Use `$WAYBAR_HOME/scripts/…` in generated `exec` paths (generators already do this).
- Add a click script sibling if needed (`*-click.sh`).

## 3. Wire settings

In [`data/waybar-settings.jsonc`](../data/waybar-settings.jsonc):

1. Add `module_intervals.<key>` (`once` or seconds).
2. Add `signals.<key>` if the module is signal-driven.
3. Append the module id to the right `groups.*.modules` list (and/or `layouts.*` if it is a top-level bar entry).
4. Add any feature block (`my_feature: { … }`) the generator or script reads.

## 4. Wire the generator

Most modules are emitted by a domain script under `scripts/generate/` that `generate-settings.sh` already calls. Either:

- Extend an existing emitter (e.g. `generate-utilities-modules.sh`, `generate-system` path inside settings generate), or
- Add `generate-<domain>-modules.sh` and invoke it from `generate-settings.sh`.

Emit JSON that includes `exec`, `interval` / `signal`, `return-type`, tooltips, and CSS `class` hooks as needed. **Do not** hand-edit `modules/*.generated.jsonc`.

## 5. CSS (optional)

- Prefer theme tokens from `theme/tokens.generated.css` / semantic colors.
- Module-specific rules go in `theme/` or `user-style.css` — avoid baking one-off colors that ignore `theme.mode`.

## 6. Regenerate and validate

```bash
make generate
make validate          # or: bash scripts/ci/validate-generated-config.sh
# If you touch generators or contracts:
bash scripts/ci/tests/generator/<relevant-suite>.sh
```

Commit updated `.generated.*` artifacts when they change (CI drift check enforces this).

## 7. Tests / CI

| Change | Suite / check |
|--------|----------------|
| Generator output / module JSON | New or extended `scripts/ci/tests/generator/*.sh` + CI matrix name |
| Secrets / polish scripts | `scripts/ci/tests/secrets/*.sh` |
| Shell contracts | Covered by `make check-contracts` |
| Python helper | `make check-python` / ruff |

After adding a suite file, ensure `.github/workflows/ci.yml` matrix lists it (`make check-suite-inventory`).

## 8. Docs

- Mention the module in the README module catalog if it is user-facing.
- Optional deps → README Dependencies tables.
- Settings keys → keep [settings-reference](settings-reference.md) in sync when adding top-level keys.

## Quick agent path

With the [MCP server](mcp.md): backup → patch groups/intervals → `waybar_generate` → `waybar_validate` → restart with confirm. Still prefer a real generator + CI suite for new modules, not only JSON patches.

## Related docs

See the full map: [Documentation index](README.md).

| Doc | Topic |
|-----|--------|
| [Architecture](architecture.md) | Where generators sit in the pipeline |
| [Settings reference](settings-reference.md) | Keys to wire (`groups`, intervals, signals) |
| [Scripts layout](../scripts/README.md) | Domain folders + growth rules |
| [Theming](theming.md) | CSS / tokens for new chrome |
| [Troubleshooting](troubleshooting.md) | Module missing / empty |
| [MCP server](mcp.md) | Optional agent edits |
| [Contributing](../CONTRIBUTING.md) | Suites and CI matrix |
| [AGENTS.md](../AGENTS.md) | Agent briefing |
