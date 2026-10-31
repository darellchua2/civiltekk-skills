#!/usr/bin/env bats

# Tests for the docling route of office-document-router-skill (PLAN-GIT-308; absorbed #680).
# Verifies skill existence, frontmatter validity, required sections,
# default-disabled MCP state, pack deep-merge correctness, AGENTS.md
# routing rule, agent skill grants, and dependency-map.json edge.
# Peer to tests/test_markitdown_skill.bats.

# Route file since #680 (skill absorbed into office-document-router-skill)
ROUTE_MD="skills/office-document-router-skill/references/routes/docling.md"
SKILL_MD="$ROUTE_MD"
AGENTS_DIR="agents"
CONFIG="deploy/opencode.json"
PACKS_DIR="deploy/packs"
MERGE_SCRIPT="deploy/merge-packs.mjs"

# =============================================================================
# Skill existence + frontmatter
# =============================================================================

@test "docling_skill_file_exists" {
  [ -f "$SKILL_MD" ]
}

@test "docling_skill_frontmatter_parses" {
  # Route files carry a Load-when header instead of frontmatter (#680)
  grep -qF '**Load when:**' "$SKILL_MD"
  grep -qF '**Skip when:**' "$SKILL_MD"
}

@test "docling_skill_required_sections_present" {
  for section in "## What this skill does" "## When to use docling" \
                 "## CLI-on-demand recipe" "## Persistent MCP recipe" \
                 "## Trust Boundary" "## Consent Policy" \
                 "## Version Pinning" "## Fallback Strategy"; do
    grep -qF "$section" "$SKILL_MD"
  done
}

@test "docling_skill_references_agents_md_routing" {
  # Since #680 the route references the ROUTER's extraction ladder (single-source)
  grep -q "router's extraction ladder" "$SKILL_MD"
}

@test "docling_skill_has_docling_convert_command" {
  # The on-demand CLI recipe must reference docling convert
  grep -q 'docling convert' "$SKILL_MD"
}

# =============================================================================
# Default-disabled MCP state
# =============================================================================

@test "docling_mcp_disabled_by_default" {
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert 'docling' in d['mcp']['servers']; assert d['mcp']['servers']['docling']['disabled'] is True, 'docling must be opt-in'"
}

@test "docling_tool_denied_by_default" {
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert any(r['action']=='docling*' and r['effect']=='deny' for r in d['permissions'])"
}

@test "docling_mcp_has_local_conversion_mode" {
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert d['mcp']['servers']['docling']['environment']['DOCLING_CONVERSION_MODE'] == 'local'"
}

# =============================================================================
# Pack deep-merge correctness
# =============================================================================

@test "pack_docling_exists" {
  [ -f "$PACKS_DIR/pack-docling.json" ]
}

@test "pack_docling_ships_server_with_disabled_false" {
  python3 -c "import json; p=json.load(open('$PACKS_DIR/pack-docling.json')); assert p['mcp']['servers']['docling']['disabled'] is False"
}

@test "pack_docling_grants_tool_permission" {
  # v2 permissions array rule, not the v1 root permission map or tools map
  python3 -c "
import json
p=json.load(open('$PACKS_DIR/pack-docling.json'))
assert {'action':'docling*','resource':'*','effect':'allow'} in p['permissions'], 'missing v2 allow rule'
assert 'permission' not in p, 'v1 root permission map is dead in v2'
assert 'tools' not in p, 'top-level tools map is deprecated'
"
}

@test "pack_docling_deep_merge_flips_config" {
  # Verify merge-packs.mjs deep-merges pack-docling.json into a temp copy
  # and flips both mcp.servers.docling.disabled and the docling* deny rule
  # (in place — no duplicate rules)
  cp "$CONFIG" /tmp/test_docling_merge.json
  node "$MERGE_SCRIPT" --config /tmp/test_docling_merge.json --packs-dir "$PACKS_DIR" --packs docling >/dev/null 2>&1
  python3 -c "
import json
d=json.load(open('/tmp/test_docling_merge.json'))
assert d['mcp']['servers']['docling']['disabled'] is False
rules=[r for r in d['permissions'] if r['action']=='docling*']
assert len(rules)==1 and rules[0]['effect']=='allow', 'deny rule must flip in place, no duplicates'
"
  rm -f /tmp/test_docling_merge.json
}

# =============================================================================
# AGENTS.md routing rule (single source of truth)
# =============================================================================

@test "agents_md_has_extraction_routing_section" {
  grep -q "Office Document Extraction Routing" AGENTS.md
}

@test "agents_md_lists_four_tiers" {
  # All 4 tiers must be named in the routing section
  for tier in "markitdown" "docling" "image-analyzer-subagent" "pdf route"; do
    grep -q "$tier" AGENTS.md
  done
}

@test "deploy_agents_md_has_no_routing_duplicate" {
  # deploy/.AGENTS.md was slimmed (e278d2d): the 4-tier routing table's single
  # home is repo-root AGENTS.md (pinned by agents_md_has_extraction_routing_section).
  # Guard against the table re-growing in the user-level file.
  ! grep -q "Office Document Extraction Routing" deploy/.AGENTS.md
}

# =============================================================================
# Agent skill grants
# =============================================================================

@test "primary_has_docling_skill_allow" {
  # #680 on-demand design: the shipped config allows the ROUTER; the docling
  # MCP pack itself stays opt-in (--enable-pack docling, consent-gated).
  python3 -c "import json; d=json.load(open('${CONFIG}')); assert any(r['action']=='skill' and r.get('resource')=='office-document-router-skill' and r['effect']=='allow' for r in d['permissions'])"
}

@test "office_document_primary_agent_has_docling_skill" {
  python3 -c "
import yaml
fm=yaml.safe_load(open('$AGENTS_DIR/office-document-router-subagent.md').read().split('---')[1])
assert any(r['action']=='skill' and r['resource']=='office-document-router-skill' and r['effect']=='allow' for r in fm['permissions']), 'docling skill rule missing'
"
}

# =============================================================================
# dependency-map.json edge (Decision 8)
# =============================================================================

@test "dependency_map_has_docling_edge" {
  # #680 on-demand design: the auto-enable impliesMcp edge is removed — the
  # docling route carries the consent-gated enablement recipe instead.
  python3 -c "import json; d=json.load(open('installer/dependency-map.json')); assert 'docling-mcp-skill' not in d['impliesMcp']; assert 'markitdown-mcp-skill' not in d['impliesMcp']"
}

# =============================================================================
# Specialist subagents reference AGENTS.md (not stale inline prose)
# =============================================================================

@test "specialist_subagents_reference_agents_md_routing" {
  for agent in "requirements-specialist-subagent" "technical-design-specialist-subagent" \
               "documentation-subagent" "discovery-specialist-subagent"; do
    echo "  checking $agent" >&3
    grep -q "AGENTS.md" "$AGENTS_DIR/$agent.md"
  done
}
