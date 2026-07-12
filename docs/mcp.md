# Waybar MCP server

> Doc map: [Documentation index](README.md) · [AGENTS.md](../AGENTS.md) · [Architecture](architecture.md)

Stdlib-only [Model Context Protocol](https://modelcontextprotocol.io/) server so AI assistants (Cursor, Claude Desktop, Windsurf, …) can inspect and safely edit this Waybar config.

Entry point: [`scripts/mcp/waybar-mcp.py`](../scripts/mcp/waybar-mcp.py) (no pip packages).

## Further reading

Full map: [Documentation index](README.md).

| Doc | Topic |
|-----|--------|
| [Architecture](architecture.md) | Pipeline overview |
| [Settings reference](settings-reference.md) | Key catalog |
| [Adding a module](adding-a-module.md) | New module checklist |
| [Theming](theming.md) | Colors / presets / wallpaper |
| [Troubleshooting](troubleshooting.md) | Common failures |
| [Contributing](../CONTRIBUTING.md) | Dev loop and checks |
| [AGENTS.md](../AGENTS.md) | Agent briefing |
| [Scripts layout](../scripts/README.md) | `scripts/mcp/` placement |
| [Root README](../README.md) | User-facing overview |

## Register

```bash
python3 ~/.config/waybar/scripts/mcp/waybar-mcp.py --register
```

Writes Cursor `~/.cursor/mcp.json`, Claude Desktop, and Windsurf when those config dirs exist, and prints a manual snippet.

### Manual Cursor config

```json
{
  "mcpServers": {
    "waybar": {
      "command": "python3",
      "args": ["/home/YOU/.config/waybar/scripts/mcp/waybar-mcp.py"]
    }
  }
}
```

Restart the AI client after registering. Override the tree with `WAYBAR_HOME` or `--waybar-home`.

## Protocol

JSON-RPC over stdin/stdout (`protocolVersion: 2024-11-05`).

| Method | Support |
|--------|---------|
| `initialize` / `initialized` | tools + resources + prompts |
| `tools/list`, `tools/call` | Full tool catalog |
| `resources/list`, `resources/read` | Stable `waybar://…` URIs |
| `prompts/list`, `prompts/get` | Guided workflows |
| `ping` | Empty result |

Logs go to **stderr** so they never corrupt the transport.

## Tools

All tool names are prefixed with `waybar_`.

### Discovery

| Tool | Role |
|------|------|
| `waybar_overview` | Compact summary (theme, bars, groups, features) |
| `waybar_describe` | Agent playbook text |
| `waybar_schema` | Top-level settings key descriptions |
| `waybar_search` | Substring search over settings |

### Settings

| Tool | Role |
|------|------|
| `waybar_get_settings` | Read path (secrets excluded by default; secret keys redacted) |
| `waybar_diff_settings` | Dry-run deep-merge preview |
| `waybar_patch_settings` | Deep-merge write (`dry_run` optional) |
| `waybar_set_path` / `waybar_unset_path` | Single-path edit |
| `waybar_backup_settings` / `waybar_list_backups` / `waybar_restore_settings` | Backup under `~/.cache/waybar/mcp-backups/` (+ sibling under `data/`) |

Programmatic writes rewrite pretty JSON into `waybar-settings.jsonc` (**JSONC comments are lost**).

### Theme / layout / groups

| Tool | Role |
|------|------|
| `waybar_list_themes` / `waybar_get_theme` / `waybar_set_theme` | Presets under `data/themes/` |
| `waybar_apply_preset` / `waybar_write_theme` | Apply colors or create a preset file |
| `waybar_list_groups` / `waybar_get_group` / `waybar_set_group_modules` | Group modules |
| `waybar_get_layout` / `waybar_set_layout_modules` | Top/bottom module lists |
| `waybar_get_bars` / `waybar_set_bars` | Bar chrome |
| `waybar_get_intervals` / `waybar_set_interval` | Poll intervals |
| `waybar_get_signals` / `waybar_set_signal` | RT signals |

### Profiles / manifests / catalog

| Tool | Role |
|------|------|
| `waybar_list_profiles` / `waybar_get_profile` / `waybar_apply_profile` | e.g. `minimal-groups` |
| `waybar_list_manifests` / `waybar_get_manifest` / `waybar_patch_manifest` | dock-apps, network-interfaces, workspace-* |
| `waybar_list_modules` / `waybar_get_module` | Generated module defs |
| `waybar_list_generated` / `waybar_read_generated` | `*.generated.*` artifacts |
| `waybar_list_scripts` / `waybar_find_script` | Script tree index |

### Generate / check / runtime

| Tool | Role |
|------|------|
| `waybar_generate` | `make generate` |
| `waybar_validate` | `validate-generated-config.sh` |
| `waybar_check_drift` | `check-generated-drift.sh` |
| `waybar_check` | Subset: `syntax` \| `python` \| `validate` \| `fast` \| `contracts` \| `ruff` |
| `waybar_status` | systemd `--user` unit state + `pgrep` |
| `waybar_restart` | Requires `confirm=true` |

Under `TEST_SUITE_RUN=1`, generate/restart log the production command line but skip host execution (or run `MOCK_BIN` stubs).

### Secrets (metadata only)

| Tool | Role |
|------|------|
| `waybar_secrets_status` | Exists / mode / structure **without values** |
| `waybar_secrets_example` | Safe example template |

**Never** writes `waybar-secrets.jsonc` or returns live secret values.

## Resources

| URI | Content |
|-----|---------|
| `waybar://overview` | Overview JSON |
| `waybar://settings` | Settings without secrets |
| `waybar://settings-raw` | SoT path note |
| `waybar://themes` | Theme index |
| `waybar://themes/{name}` | Theme body |
| `waybar://manifests/{id}` | Allowlisted manifest |
| `waybar://docs/mcp` | This document |
| `waybar://docs/readme` | Root README |

## Prompts

| Prompt | Purpose |
|--------|---------|
| `customize_theme` | Switch preset/mode + generate |
| `minimal_profile` | Apply `minimal-groups` |
| `add_module_to_group` | Insert module into a group |
| `tune_intervals` | Batch interval updates |
| `floating_bar` | Enable floating geometry |
| `homelab_targets` | Edit `homelab.targets` |
| `after_edit_workflow` | Backup → generate → validate → restart |

## Security notes

- Theme/profile/manifest names are allowlisted (`^[a-z0-9_-]+$`); path traversal rejected.
- Secret-looking overlay keys (`pass`, `token`, …) are refused on write.
- Subprocesses are limited to `make`, CI scripts, and `systemctl --user`.
- Do not hand-edit `*.generated.jsonc` / `*.generated.css` — use settings + `waybar_generate`.

## Tests

```bash
bash scripts/ci/tests/generator/mcp-server.sh
# or: CI generator matrix shard `mcp-server`
```
