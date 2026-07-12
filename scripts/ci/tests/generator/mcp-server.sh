#!/usr/bin/env bash
# Behavioral tests for scripts/mcp/waybar-mcp.py (JSON-RPC MCP server).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "mcp-server"
waybar_test_gen_sandbox

export XDG_CACHE_HOME="$TEST_DIR/cache"
# Force MCP into safe skip/stub mode (no real systemctl/make on the host).
export TEST_SUITE_RUN=1
mkdir -p "$XDG_CACHE_HOME" "$TEST_DIR/mock-bin"
export MOCK_BIN="$TEST_DIR/mock-bin"

MCP_PY="$TEST_DIR/scripts/mcp/waybar-mcp.py"
if [[ ! -f "$MCP_PY" ]]; then
  waybar_test_fail "missing $MCP_PY"
  waybar_test_end
fi

mapfile -t EXPECTED_TOOLS < <(
  WAYBAR_HOME="$TEST_DIR" python3 - <<'PY'
import importlib.util
import os
import sys
from pathlib import Path

mcp = Path(os.environ["WAYBAR_HOME"]) / "scripts" / "mcp"
sys.path.insert(0, str(mcp))
spec = importlib.util.spec_from_file_location("tools", mcp / "tools.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
for name in mod.all_tool_names():
    print(name)
PY
)

tool_call() {
  local name="$1"
  local args="${2:-"{}"}"
  local id="${3:-99}"
  python3 -c '
import json, sys
print(json.dumps({
  "jsonrpc": "2.0",
  "id": int(sys.argv[1]),
  "method": "tools/call",
  "params": {"name": sys.argv[2], "arguments": json.loads(sys.argv[3])},
}))
' "$id" "$name" "$args"
}

run_mcp() {
  WAYBAR_HOME="$TEST_DIR" printf '%s\n' "$@" | python3 "$MCP_PY" 2>/dev/null
}

run_mcp_stderr() {
  { WAYBAR_HOME="$TEST_DIR" printf '%s\n' "$@" | python3 "$MCP_PY" >/dev/null; } 2>&1
}

assert_contains() { waybar_test_assert_contains "$@"; }
assert_not_contains() { waybar_test_assert_not_contains "$@"; }
assert_file_exists() { waybar_test_assert_file_exists "$@"; }

# --- initialize / capabilities ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
assert_contains "$resp" '"protocolVersion"' "initialize has protocolVersion"
assert_contains "$resp" '"tools"' "initialize capabilities include tools"
assert_contains "$resp" '"resources"' "initialize capabilities include resources"
assert_contains "$resp" '"prompts"' "initialize capabilities include prompts"
assert_contains "$resp" 'waybar-mcp' "initialize serverInfo name"

# --- tools/list ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
if [[ "${#EXPECTED_TOOLS[@]}" -lt 40 ]]; then
  waybar_test_fail "expected many tools, got ${#EXPECTED_TOOLS[@]}"
fi
for tool in "${EXPECTED_TOOLS[@]}"; do
  assert_contains "$resp" "\"$tool\"" "tools/list includes $tool"
done

# --- resources / prompts ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}')
assert_contains "$resp" 'waybar://overview' "resources/list includes overview"
assert_contains "$resp" 'waybar://settings' "resources/list includes settings"

resp=$(run_mcp '{"jsonrpc":"2.0","id":4,"method":"prompts/list","params":{}}')
assert_contains "$resp" 'customize_theme' "prompts/list includes customize_theme"
assert_contains "$resp" 'after_edit_workflow' "prompts/list includes after_edit_workflow"

resp=$(run_mcp '{"jsonrpc":"2.0","id":5,"method":"prompts/get","params":{"name":"after_edit_workflow","arguments":{}}}')
assert_contains "$resp" 'waybar_generate' "prompts/get after_edit_workflow mentions generate"

# --- unknown method ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":6,"method":"not/a/method","params":{}}')
assert_contains "$resp" '"error"' "unknown method returns error"
# -32601 = JSON-RPC Method not found
assert_contains "$resp" '-32601' "unknown method code -32601"

# --- overview / get_settings ---
resp=$(run_mcp "$(tool_call waybar_overview '{}')")
assert_contains "$resp" 'waybar_home' "overview includes waybar_home"
assert_contains "$resp" 'theme' "overview includes theme"

resp=$(run_mcp "$(tool_call waybar_get_settings '{"path":"theme.mode"}')")
assert_contains "$resp" '"text"' "get_settings returns text content"

# --- secrets redaction ---
waybar_test_write_secrets <<'EOF'
{
  "services": {
    "i2pd": { "console_pass": "SUPER_SECRET_PASS" }
  }
}
EOF
resp=$(run_mcp "$(tool_call waybar_get_settings '{"path":"services","include_secrets":true}')")
assert_not_contains "$resp" 'SUPER_SECRET_PASS' "get_settings redacts secret values"
assert_contains "$resp" 'REDACTED' "get_settings marks redacted secrets"

resp=$(run_mcp "$(tool_call waybar_secrets_status '{}')")
assert_not_contains "$resp" 'SUPER_SECRET_PASS' "secrets_status never returns values"
assert_contains "$resp" 'structure' "secrets_status includes structure"

# --- patch / diff / set_path / unset_path ---
resp=$(run_mcp "$(tool_call waybar_diff_settings '{"overlay":{"theme":{"font_size":99}}}')")
assert_contains "$resp" 'dry_run' "diff_settings is dry_run"

resp=$(run_mcp "$(tool_call waybar_set_path '{"path":"theme.font_size","value":42}')")
assert_contains "$resp" 'written' "set_path writes"

resp=$(run_mcp "$(tool_call waybar_get_settings '{"path":"theme.font_size"}')")
assert_contains "$resp" '42' "font_size updated to 42"

resp=$(run_mcp "$(tool_call waybar_unset_path '{"path":"theme.font_size"}')")
assert_contains "$resp" 'written' "unset_path writes"

resp=$(run_mcp "$(tool_call waybar_patch_settings '{"overlay":{"theme":{"font_size":13}},"dry_run":true}')")
assert_contains "$resp" 'dry_run' "patch_settings dry_run"

resp=$(run_mcp "$(tool_call waybar_patch_settings '{"overlay":{"services":{"i2pd":{"console_pass":"x"}}}}')")
assert_contains "$resp" 'isError' "patch refuses secret-looking keys"
assert_contains "$resp" 'secret' "patch secret rejection mentions secret"

# --- backup / restore ---
resp=$(run_mcp "$(tool_call waybar_backup_settings '{}')")
assert_contains "$resp" 'backup' "backup_settings returns backup path"
backup_path=$(
  python3 -c '
import json, sys
outer = json.loads(sys.argv[1])
text = outer["result"]["content"][0]["text"]
print(json.loads(text)["backup"])
' "$resp"
)
resp=$(run_mcp "$(tool_call waybar_list_backups '{}')")
assert_contains "$resp" 'waybar-settings.jsonc.bak.' "list_backups finds backup"

restore_args=$(python3 -c 'import json,sys; print(json.dumps({"backup_path": sys.argv[1]}))' "$backup_path")
resp=$(run_mcp "$(tool_call waybar_restore_settings "$restore_args")")
assert_contains "$resp" 'restored_from' "restore_settings works"

# --- themes ---
resp=$(run_mcp "$(tool_call waybar_list_themes '{}')")
assert_contains "$resp" 'nord' "list_themes includes nord"

resp=$(run_mcp "$(tool_call waybar_get_theme '{"name":"nord"}')")
assert_contains "$resp" 'colors' "get_theme returns colors"

resp=$(run_mcp "$(tool_call waybar_get_theme '{"name":"../../etc/passwd"}')")
assert_contains "$resp" 'isError' "get_theme rejects traversal"

resp=$(run_mcp "$(tool_call waybar_set_theme '{"mode":"preset","preset":"nord"}')")
assert_contains "$resp" 'nord' "set_theme sets nord"

resp=$(run_mcp "$(tool_call waybar_apply_preset '{"name":"gruvbox"}')")
assert_contains "$resp" 'gruvbox' "apply_preset applies gruvbox"

# --- groups / layouts / intervals / signals ---
resp=$(run_mcp "$(tool_call waybar_list_groups '{}')")
assert_contains "$resp" 'hardware' "list_groups includes hardware"

resp=$(run_mcp "$(tool_call waybar_get_group '{"name":"media"}')")
assert_contains "$resp" 'modules' "get_group returns modules"

resp=$(run_mcp "$(tool_call waybar_set_interval '{"key":"cpu","value":9}')")
assert_contains "$resp" 'cpu' "set_interval returns key"
assert_contains "$resp" '9' "set_interval returns value"

# Prefer escaped-safe needles for nested JSON text payloads:
resp=$(run_mcp "$(tool_call waybar_set_interval '{"key":"gpu","value":11}')")
assert_contains "$resp" 'gpu' "set_interval gpu returns key"
assert_contains "$resp" '11' "set_interval gpu returns value"

resp=$(run_mcp "$(tool_call waybar_set_signal '{"key":"mic","value":7}')")
assert_contains "$resp" 'mic' "set_signal returns key"
assert_contains "$resp" '7' "set_signal returns value"

resp=$(run_mcp "$(tool_call waybar_set_bars '{"patch":{"floating":true}}')")
assert_contains "$resp" 'floating' "set_bars works"

resp=$(run_mcp "$(tool_call waybar_get_layout '{"bar":"top"}')")
assert_contains "$resp" 'modules_left' "get_layout top works"

# --- profiles / manifests ---
resp=$(run_mcp "$(tool_call waybar_list_profiles '{}')")
assert_contains "$resp" 'minimal-groups' "list_profiles includes minimal-groups"

resp=$(run_mcp "$(tool_call waybar_apply_profile '{"name":"minimal-groups","dry_run":true}')")
assert_contains "$resp" 'dry_run' "apply_profile dry_run"

resp=$(run_mcp "$(tool_call waybar_list_manifests '{}')")
assert_contains "$resp" 'dock-apps' "list_manifests includes dock-apps"

resp=$(run_mcp "$(tool_call waybar_get_manifest '{"id":"dock-apps"}')")
assert_contains "$resp" '"text"' "get_manifest returns content"

resp=$(run_mcp "$(tool_call waybar_patch_manifest '{"id":"secrets-example","overlay":{}}')")
assert_contains "$resp" 'isError' "patch_manifest refuses secrets-example"

# --- modules / scripts ---
resp=$(run_mcp "$(tool_call waybar_list_modules '{}')")
assert_contains "$resp" 'modules' "list_modules returns modules key"

resp=$(run_mcp "$(tool_call waybar_list_generated '{}')")
assert_contains "$resp" '"text"' "list_generated returns text"

resp=$(run_mcp "$(tool_call waybar_list_scripts '{}')")
assert_contains "$resp" 'mcp' "list_scripts includes mcp domain"

resp=$(run_mcp "$(tool_call waybar_find_script '{"query":"cpu"}')")
assert_contains "$resp" '"text"' "find_script returns text"

# --- generate / validate / restart under TEST_SUITE_RUN ---
log=$(run_mcp_stderr "$(tool_call waybar_generate '{}')")
assert_contains "$log" 'make' "generate logs make command"
assert_contains "$log" 'Skipping host execution' "generate skips host under TEST_SUITE_RUN"

log=$(run_mcp_stderr "$(tool_call waybar_restart '{"confirm":true}')")
assert_contains "$log" 'systemctl' "restart logs systemctl"
assert_contains "$log" 'Skipping host execution' "restart skips host under TEST_SUITE_RUN"

resp=$(run_mcp "$(tool_call waybar_restart '{"confirm":false}')")
assert_contains "$resp" 'isError' "restart without confirm errors"
assert_contains "$resp" 'confirm=true' "restart without confirm mentions confirm"

resp=$(run_mcp "$(tool_call waybar_check '{"subset":"not-a-subset"}')")
assert_contains "$resp" 'isError' "check rejects invalid subset"

# --- unknown tool ---
resp=$(run_mcp "$(tool_call not_a_real_tool '{}')")
assert_contains "$resp" 'isError' "unknown tool isError"
assert_contains "$resp" 'Unknown tool' "unknown tool message"

# --- resources/read ---
resp=$(run_mcp '{"jsonrpc":"2.0","id":50,"method":"resources/read","params":{"uri":"waybar://overview"}}')
assert_contains "$resp" 'waybar_home' "resources/read overview works"

resp=$(run_mcp '{"jsonrpc":"2.0","id":51,"method":"resources/read","params":{"uri":"waybar://themes/../etc"}}')
assert_contains "$resp" '"error"' "resources/read rejects traversal URI"

# --- --register / --help / --version ---
FAKE_HOME=$(mktemp -d)
mkdir -p "$FAKE_HOME/.config/Claude" "$FAKE_HOME/.codeium/windsurf" "$FAKE_HOME/.cursor"
echo '{}' >"$FAKE_HOME/.config/Claude/claude_desktop_config.json"
out=$(HOME="$FAKE_HOME" python3 "$MCP_PY" --register 2>&1) || true
assert_contains "$out" 'Registering' "register prints Registering"
assert_contains "$out" 'waybar' "register mentions waybar"
assert_file_exists "$FAKE_HOME/.cursor/mcp.json" "Cursor mcp.json created"
cursor_cfg=$(cat "$FAKE_HOME/.cursor/mcp.json")
assert_contains "$cursor_cfg" 'waybar' "Cursor config has waybar server"
assert_contains "$cursor_cfg" 'waybar-mcp.py' "Cursor config points at waybar-mcp.py"
rm -rf "$FAKE_HOME"

out=$(python3 "$MCP_PY" --help 2>&1)
assert_contains "$out" 'usage:' "--help prints usage"

out=$(python3 "$MCP_PY" --version 2>&1)
assert_contains "$out" 'waybar-mcp' "--version prints name"

rc=0
out=$(python3 "$MCP_PY" --invalid-flag 2>&1) || rc=$?
if [[ "$rc" -eq 0 ]]; then
  waybar_test_fail "invalid flag should fail"
fi

waybar_test_end
