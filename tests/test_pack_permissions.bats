#!/usr/bin/env bats

# Tests for MCP provider pack permission rules (issue #370; v2 shapes, PLAN-374).
# All MCP packs must flip server state via `mcp.servers.<name>.disabled: false`
# and permissions via `permissions` array rules ({action, resource, effect}),
# never the v1 `enabled` flag, the v1 root `permission` map, the deprecated
# top-level `tools` map, or the inert nested `permission.tool` key.

MERGE_SCRIPT="deploy/merge-packs.mjs"
SETUP="deploy/setup.sh"
SETUP_PS1="deploy/setup.ps1"

# pack-name:server-keys pairs (explicit enumeration — no dir glob)
PACK_SERVERS="markitdown:markitdown docling:docling chrome-devtools:chrome-devtools nextjs:next-devtools playwright:playwright alpha-vantage:alpha-vantage nanobanana:nanobanana"

# =============================================================================
# Pack file shape (all MCP packs)
# =============================================================================

@test "all_mcp_packs_exist_and_are_valid_json" {
  for entry in $PACK_SERVERS; do
    pack="${entry%%:*}"
    f="deploy/packs/pack-${pack}.json"
    [ -f "$f" ]
    node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))"
  done
}

@test "mcp_packs_use_v2_permissions_array_rules" {
  for entry in $PACK_SERVERS; do
    pack="${entry%%:*}"
    node -e "
      const p = JSON.parse(require('fs').readFileSync('deploy/packs/pack-${pack}.json','utf8'));
      const keys = Object.keys(p);
      if (keys[0] !== '\$comment') { console.error('${pack}: \$comment must be first key (merge-packs stripJsonComments strips whole-line entries only)'); process.exit(1); }
      if (p.tools !== undefined) { console.error('${pack}: top-level tools is deprecated'); process.exit(1); }
      if (p.permission !== undefined) { console.error('${pack}: v1 root permission map is dead in v2 — use permissions array'); process.exit(1); }
      if (!Array.isArray(p.permissions) || p.permissions.length === 0) { console.error('${pack}: permissions array required'); process.exit(1); }
      for (const r of p.permissions) {
        if (typeof r.action !== 'string' || !r.action.endsWith('*')) { console.error('${pack}: rule action ' + JSON.stringify(r.action) + ' must be a wildcard pattern'); process.exit(1); }
        if (r.effect !== 'allow') { console.error('${pack}: rule effect must be \"allow\" (got ' + JSON.stringify(r.effect) + ')'); process.exit(1); }
        if (typeof r.resource !== 'string') { console.error('${pack}: rule resource must be a string'); process.exit(1); }
      }
    "
  done
}

@test "mcp_packs_ship_servers_with_disabled_false" {
  for entry in $PACK_SERVERS; do
    pack="${entry%%:*}"
    servers="${entry#*:}"
    node -e "
      const p = JSON.parse(require('fs').readFileSync('deploy/packs/pack-${pack}.json','utf8'));
      const want = '${servers}'.split(',');
      for (const s of want) {
        const def = p.mcp && p.mcp.servers && p.mcp.servers[s];
        if (!def) { console.error('${pack}: missing mcp.servers.' + s); process.exit(1); }
        if (def.disabled !== false) { console.error('${pack}: mcp.servers.' + s + '.disabled must be false'); process.exit(1); }
        if (def.enabled !== undefined) { console.error('${pack}: v1 enabled key is dead in v2 (mcp.servers.' + s + ')'); process.exit(1); }
        const extra = Object.keys(def).filter((k) => k !== 'disabled');
        if (extra.length > 0) { console.error('${pack}: flip-only contract violated — mcp.servers.' + s + ' carries ' + JSON.stringify(extra) + ' (definitions belong in the base config, #558)'); process.exit(1); }
      }
    "
  done
}

# =============================================================================
# merge-packs semantics: pack allow flips a v2 deny rule in place (the #370 bug class)
# =============================================================================

@test "pack_merge_flips_disabled_and_deny_rule_in_place" {
  local dir
  dir="$(mktemp -d)"
  cat > "$dir/opencode.json" <<'EOF'
{
  "mcp": { "servers": { "markitdown": { "type": "local", "command": ["markitdown-mcp"], "disabled": true } } },
  "permissions": [
    { "action": "codegraph*", "resource": "*", "effect": "deny" },
    { "action": "markitdown*", "resource": "*", "effect": "deny" }
  ]
}
EOF
  node "$MERGE_SCRIPT" --config "$dir/opencode.json" --packs-dir deploy/packs --packs markitdown >/dev/null
  node -e "
    const c = JSON.parse(require('fs').readFileSync('$dir/opencode.json','utf8'));
    if (c.mcp.servers.markitdown.disabled !== false) { console.error('disabled must flip to false'); process.exit(1); }
    const rules = c.permissions.filter((r) => r.action === 'markitdown*');
    if (rules.length !== 1) { console.error('no duplicate rules allowed, got ' + rules.length); process.exit(1); }
    if (rules[0].effect !== 'allow') { console.error('deny rule must flip to allow, got ' + JSON.stringify(rules[0])); process.exit(1); }
    if (c.permissions[0].action !== 'codegraph*') { console.error('rule order must be preserved (in-place replace)'); process.exit(1); }
    if (c.permissions.length !== 2) { console.error('array length must be unchanged, got ' + c.permissions.length); process.exit(1); }
  "
  rm -rf "$dir"
}

@test "pack_merge_fails_loud_on_definition_less_target" {
  local dir
  dir="$(mktemp -d)"
  # #558: flip-only pack + target lacking the server definition = the stale-config
  # stub trap; must die before the write (target byte-unchanged).
  cat > "$dir/opencode.json" <<'JSON'
{ "mcp": { "servers": {} }, "permissions": [] }
JSON
  cp "$dir/opencode.json" "$dir/before.json"
  run node "$MERGE_SCRIPT" --config "$dir/opencode.json" --packs-dir deploy/packs --packs markitdown
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "no full definition"
  cmp -s "$dir/opencode.json" "$dir/before.json"
  rm -rf "$dir"
}

@test "pack_merge_succeeds_when_target_has_full_definition" {
  local dir
  dir="$(mktemp -d)"
  cat > "$dir/opencode.json" <<'JSON'
{ "mcp": { "servers": { "markitdown": { "type": "local", "command": ["markitdown-mcp"], "disabled": true } } }, "permissions": [] }
JSON
  node "$MERGE_SCRIPT" --config "$dir/opencode.json" --packs-dir deploy/packs --packs markitdown >/dev/null
  node -e "
    const c = JSON.parse(require('fs').readFileSync('$dir/opencode.json','utf8'));
    if (c.mcp.servers.markitdown.disabled !== false) { console.error('must flip'); process.exit(1); }
    if (!Array.isArray(c.mcp.servers.markitdown.command)) { console.error('definition must survive'); process.exit(1); }
  "
  rm -rf "$dir"
}

@test "pack_merge_preserves_unrelated_permission_rules" {
  local dir
  dir="$(mktemp -d)"
  # Full markitdown definition required: #558's stub guard fails a flip into
  # a definition-less target (the exact stale-config bug class this guards).
  cat > "$dir/opencode.json" <<'EOF'
{
  "mcp": { "servers": { "markitdown": { "type": "local", "command": ["markitdown-mcp"], "disabled": true } } },
  "permissions": [
    { "action": "codegraph*", "resource": "*", "effect": "allow" },
    { "action": "docling*", "resource": "*", "effect": "deny" },
    { "action": "read", "resource": "mcp:*", "effect": "deny" }
  ]
}
EOF
  node "$MERGE_SCRIPT" --config "$dir/opencode.json" --packs-dir deploy/packs --packs markitdown >/dev/null
  node -e "
    const c = JSON.parse(require('fs').readFileSync('$dir/opencode.json','utf8'));
    const byAction = (a) => c.permissions.find((r) => r.action === a);
    if (!byAction('codegraph*') || byAction('codegraph*').effect !== 'allow') { console.error('unrelated allow must survive'); process.exit(1); }
    if (!byAction('docling*') || byAction('docling*').effect !== 'deny') { console.error('unrelated deny must survive'); process.exit(1); }
    const rd = byAction('read');
    if (!rd || rd.resource !== 'mcp:*' || rd.effect !== 'deny') { console.error('distinct-resource rule must survive'); process.exit(1); }
    if (c.permissions.length !== 4) { console.error('markitdown allow must be appended (4 rules), got ' + c.permissions.length); process.exit(1); }
  "
  rm -rf "$dir"
}

# =============================================================================
# Install-on-enable surface (setup.sh + setup.ps1 mirror)
# =============================================================================

@test "setup_sh_installer_has_installed_check" {
  # #677: pins live in the pack JSON install block now — setup.sh carries the
  # generic installer only. The exact alpha pin AND the mcp[cli] co-install
  # (docling-mcp shares the mcp 2.x SDK) are pack data.
  grep -qF '"pipShow": "markitdown-mcp"' deploy/packs/pack-markitdown.json
  grep -qF '"markitdown-mcp==0.0.1a7"' deploy/packs/pack-markitdown.json
  grep -qF '"mcp[cli]>=2.1.1,<3.0.0"' deploy/packs/pack-markitdown.json
  grep -q 'install_pack_runtime' "$SETUP"
}

@test "setup_sh_run_pack_merger_gates_install_on_enable_pack" {
  # #677: the hook is dry-run-safe and pack-agnostic — iterates requested
  # packs through install_pack_runtime (which no-ops for config-only packs).
  local hook
  hook="$(sed -n '/run_pack_merger()/,/^}/p' "$SETUP")"
  [[ "$hook" == *'install_pack_runtime'* ]]
  [[ "$hook" == *'DRY_RUN'* ]]
}

@test "pack_install_blocks_are_schema_valid" {
  # #677 install-block contract: runtime ∈ pip|npm|none; packages non-empty
  # when runtime ≠ none; idempotent probes reference a pipShow package.
  python3 - << 'PYEOF'
import json, glob, sys
for f in glob.glob("deploy/packs/pack-*.json"):
    p = json.load(open(f))
    inst = p.get("install")
    if inst is None:
        continue
    rt = inst.get("runtime")
    assert rt in ("pip", "npm", "none"), f"{f}: bad runtime {rt!r}"
    if rt != "none":
        pkgs = inst.get("packages")
        assert isinstance(pkgs, list) and pkgs, f"{f}: packages must be a non-empty array"
    idem = inst.get("idempotent") or {}
    if idem:
        assert idem.get("pipShow"), f"{f}: idempotent requires pipShow"
print("ok")
PYEOF
}

@test "merge_packs_never_writes_install_block_into_config" {
  # #677 (arch review): merge-packs deep-merges unknown pack keys — the
  # reserved-key strip must keep `install` / `$*` metadata out of the
  # deployed config.
  local tmp
  tmp="$(mktemp)"
  cp deploy/opencode.json "$tmp"
  node "$MERGE_SCRIPT" --config "$tmp" --packs-dir deploy/packs --packs markitdown >/dev/null 2>&1
  ! grep -q '"install"' "$tmp"
  ! grep -q '"\$install-notes"' "$tmp"
  rm -f "$tmp"
}

@test "setup_ps1_is_thin_launcher_hook_inherited_from_bash" {
  # #474: the markitdown rc-gated install hook lives in setup.sh
  # (pinned above); the ps1 forwards to it and keeps no copy.
  grep -q 'setup.sh' "$SETUP_PS1"
  run grep -q 'mergeRc' "$SETUP_PS1"
  [ "$status" -ne 0 ]
}

@test "installer_has_pep668_break_system_packages_fallback" {
  # Debian 12+/Ubuntu 23.04+ block plain `pip install --user` (PEP 668);
  # the installer must detect and retry with --break-system-packages.
  grep -q 'externally-managed-environment' "$SETUP"
  grep -q -- '--break-system-packages' "$SETUP"
  # #474: the ps1 thin launcher keeps no pip logic of its own — PEP 668
  # handling is inherited by delegation to setup.sh.
  run grep -q 'externally-managed-environment' "$SETUP_PS1"
  [ "$status" -ne 0 ]
}

@test "setup_ps1_launcher_propagates_exit_code" {
  # #474: the old ps1 reset $global:LASTEXITCODE inside Invoke-PackMerger;
  # the thin launcher instead propagates bash's exit code to the caller.
  grep -q 'exit \$LASTEXITCODE' "$SETUP_PS1"
}

@test "no_doc_teaches_dead_permission_keys" {
  # Class regression guard (#269, #310, #370): no doc may instruct users to
  # write the dead keys (nested permission.tool, legacy top-level tools).
  # Covers the skills/agents tree and repo-root docs.
  # markitdown-mcp-skill/SKILL.md is whitelisted — it carries the explanatory
  # migration note.
  local hits
  hits="$(grep -rnE 'permission\.tool|tools\."|tools\["|"tools"[[:space:]]*:|`tools` block|`tools` map|tools\.<ns>|`tools\.\*`' \
    --include='*.md' skills agents MIGRATION.md README.md deploy/.AGENTS.md 2>/dev/null \
    | grep -v 'skills/markitdown-mcp-skill/SKILL.md' || true)"
  if [ -n "${hits//[[:space:]]/}" ]; then echo "$hits" >&2; fi
  [ -z "${hits//[[:space:]]/}" ]
}
