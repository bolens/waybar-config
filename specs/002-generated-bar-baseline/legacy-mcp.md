# Retrospective MCP contracts

Inspected revision: `cf333defce09672c36774720d209531ffe891e2c`, 2026-09-06.
This extends the baseline after implementation. FR-006 through FR-012 are
corrections from this audit. The non-MCP source audit remains in progress.

The catalog in [tools.py](../../scripts/mcp/tools.py) owns exact argument schemas.
The contracts below cover all 48 tools. The existing
[MCP suite](../../scripts/ci/tests/generator/mcp-server.sh) uses a disposable tree
and skips or stubs host commands. Catalog assertions establish exposure, not
coverage of every optional argument or live operation.

| Contract | Tools | Behavior and limits | Source |
| --- | --- | --- | --- |
| MC-001 | `waybar_overview`, `waybar_describe`, `waybar_schema` | Summarize configuration, source locations, settings sections and edit/generate/validate/restart order. These reads do not generate or restart. | [settings_ops.py](../../scripts/mcp/settings_ops.py) |
| MC-002 | `waybar_get_settings`, `waybar_search` | Reads omit private overlays by default; merged reads redact before dotted selection. Missing paths return null. Search matches keys/string values in public settings, with a limit, without loading the private overlay. | [settings_ops.py](../../scripts/mcp/settings_ops.py) |
| MC-003 | `waybar_diff_settings`, `waybar_patch_settings`, `waybar_set_path`, `waybar_unset_path` | Deep merge replaces non-object values. Diff/dry-run preserve files. Writes emit pretty JSON to source and compiled files, losing comments; the two writes are not transactional. Patch/set reject nested secret-looking keys. Empty set/unset paths fail; setting creates missing parents. | [settings_ops.py](../../scripts/mcp/settings_ops.py) |
| MC-004 | `waybar_backup_settings`, `waybar_list_backups`, `waybar_restore_settings` | Back up to timestamped cache/data siblings; list resolved paths. Restore requires an allowed directory and backup-looking filename. Malformed/non-object backups preserve both settings files. Valid restoration retains source comments and refreshes compiled JSON. Seconds-resolution timestamps do not guarantee unique backups in one second. | [settings_ops.py](../../scripts/mcp/settings_ops.py) |
| MC-005 | `waybar_list_themes`, `waybar_get_theme`, `waybar_set_theme`, `waybar_apply_preset`, `waybar_write_theme` | Read presets, change mode/preset/wallpaper fields, or copy preset colors and common font/geometry fields. Apply defaults to static mode. Names reject traversal; selecting requires an existing preset. Overwriting a preset requires boolean confirmation. Calls do not generate CSS or restart. | [theme_ops.py](../../scripts/mcp/theme_ops.py) |
| MC-006 | `waybar_list_groups`, `waybar_get_group`, `waybar_set_group_modules`, `waybar_get_layout`, `waybar_set_layout_modules`, `waybar_get_bars`, `waybar_set_bars` | Read groups/layouts/chrome, replace module string arrays and shallow-patch bar fields. Unknown groups and unsupported bar/side names fail. Layout writes can create missing supported bars. Writes follow MC-003's comment/synchronization policy. | [layout_ops.py](../../scripts/mcp/layout_ops.py) |
| MC-007 | `waybar_get_intervals`, `waybar_set_interval`, `waybar_get_signals`, `waybar_set_signal` | Set nonempty map keys. Intervals accept integer values or `once`, excluding booleans. Signals use declared integer arguments. Setters do not establish uniqueness, OS signal ranges or positive intervals; generated-config checks own further constraints. | [layout_ops.py](../../scripts/mcp/layout_ops.py) |
| MC-008 | `waybar_list_profiles`, `waybar_get_profile`, `waybar_apply_profile`, `waybar_list_manifests`, `waybar_get_manifest`, `waybar_patch_manifest` | Profiles deep-merge object overlays with optional dry-run. Manifest IDs use a fixed allowlist; object patches support previews and reject the secrets-example manifest. These helpers do not edit the private overlay. | [manifest_ops.py](../../scripts/mcp/manifest_ops.py) |
| MC-009 | `waybar_list_modules`, `waybar_get_module`, `waybar_list_generated`, `waybar_read_generated`, `waybar_list_scripts`, `waybar_find_script` | Enumerate modules, generated artifacts and shell/Python scripts. Generated reads require generated-looking relative paths confined after resolution to allowed output directories. Module listing can skip malformed files. Script search normalizes module prefixes/underscores and limits results to 50. | [catalog_ops.py](../../scripts/mcp/catalog_ops.py) |
| MC-010 | `waybar_generate`, `waybar_validate`, `waybar_check_drift`, `waybar_check`, `waybar_status`, `waybar_restart` | Invoke fixed commands/check subsets with timeouts and report status/output. Status reads user-unit/process state. Restart requires boolean true. Test mode skips or substitutes commands and explicitly reports skips. Fixtures do not prove live restart. | [run_ops.py](../../scripts/mcp/run_ops.py) |
| MC-011 | `waybar_secrets_status`, `waybar_secrets_example` | Return existence, permissions and value-free structure, or public example text. Missing overlay is valid status; malformed overlay reports a structure error. Neither tool changes credentials or permissions. | [secrets_ops.py](../../scripts/mcp/secrets_ops.py) |
| MC-012 | All tools | Validate catalog type, required, enum and array-item rules before dispatch. Invalid arguments fail before side effects. Unknown tools and handler failures return error results. This validates the catalog's schema subset, not general JSON Schema. | [tools.py](../../scripts/mcp/tools.py) |

## Transport, resources and prompts

[waybar-mcp.py](../../scripts/mcp/waybar-mcp.py) uses line-delimited JSON-RPC on
stdin/stdout and logs to stderr. Initialization advertises the version from
[protocol.py](../../scripts/mcp/protocol.py), server identity and capabilities.
Ping returns an empty result. Invalid JSON, requests and parameter envelopes
return errors; notifications remain silent and do not invoke request-only
handlers. Later valid requests remain usable. Unknown methods return an error.

[resources.py](../../scripts/mcp/resources.py) exposes six fixed resources:
overview, public redacted settings, a source-path pointer, theme index, MCP docs
and README. Named themes and allowlisted manifests add dynamic resources.
Unknown/traversing URIs or missing files produce errors. The raw-settings
resource returns a pointer rather than unredacted file contents.

[prompts.py](../../scripts/mcp/prompts.py) renders seven workflows: theme,
minimal profile, adding a grouped module, intervals, floating bars, homelab
targets and after-edit validation. Rendering performs no operational action.
Declared required arguments and string argument values are validated before
rendering; invalid requests return invalid-parameters errors (FR-014).

`--version` prints identity; `--waybar-home` selects a tree. `--register` targets
existing Claude Desktop, Windsurf and Cursor config directories and prints a
manual snippet. Invalid existing configuration is preserved; valid configs retain unrelated
entries, and any attempted failure returns nonzero (FR-013). No live client
registration was performed.

## Evidence

Focused MCP and shared-parser regressions pass. The full gate was interrupted
before completion and must run again. Historical baseline receipts do not prove
this candidate or completion of the remaining runtime/generator audit.
