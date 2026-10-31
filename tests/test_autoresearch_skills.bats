#!/usr/bin/env bats

# Tests for autoresearch new skills + subagents (Phase 1 + Phase 2 deliverables).
#
# NOTE: bats 1.13+ parses `@test` blocks textually (the preprocessor extracts
# them via regex on source text before any shell evaluation), so the
# `eval "@test ..."` pattern from older bats versions no longer works.
# Tests are therefore written as explicit @test blocks.

SKILLS_DIR="skills"
AGENTS_DIR="agents"

# =============================================================================
# New skills — YAML validation for all 4 new skills
# =============================================================================

@test "new_skill_autoresearch-core_yaml_validates" {
  skill_md="$SKILLS_DIR/autoresearch-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); yaml.safe_load(d.split('---')[1])"
}

@test "route_autoresearch-ml_file_validates" {
  # #688: loop skills absorbed as router routes — header check replaces frontmatter
  route_md="$SKILLS_DIR/autoresearch-skill/references/routes/ml.md"
  [ -f "$route_md" ]
  grep -qF '**Load when:**' "$route_md"
  grep -qF '**Skip when:**' "$route_md"
}

@test "route_autoresearch-code_file_validates" {
  # #688: loop skills absorbed as router routes — header check replaces frontmatter
  route_md="$SKILLS_DIR/autoresearch-skill/references/routes/code.md"
  [ -f "$route_md" ]
  grep -qF '**Load when:**' "$route_md"
  grep -qF '**Skip when:**' "$route_md"
}

@test "route_autoresearch-research_file_validates" {
  # #688: loop skills absorbed as router routes — header check replaces frontmatter
  route_md="$SKILLS_DIR/autoresearch-skill/references/routes/research.md"
  [ -f "$route_md" ]
  grep -qF '**Load when:**' "$route_md"
  grep -qF '**Skip when:**' "$route_md"
}

# =============================================================================
# Subagent model-tier assertions (v2.0: agents are model-free in source;
# concrete models are injected at deploy time via installer/agent-tiers.json)
# =============================================================================

@test "subagent_autoresearch_ml_no_hardcoded_model_in_frontmatter" {
  agent_md="$AGENTS_DIR/autoresearch-ml-subagent.md"
  [ -f "$agent_md" ]
  # Source agents must NOT have a model: line in frontmatter (injected at deploy)
  ! python3 -c "
import yaml
d=open('$agent_md').read()
fm=yaml.safe_load(d.split('---')[1])
assert 'model' not in fm, f'frontmatter must not contain model (v2.0), got: {fm.get(\"model\")}'
"
  # Verify it IS in agent-tiers.json under 'long-context' tier
  python3 -c "
import json
data=json.load(open('installer/agent-tiers.json'))
tiers=data['tiers']
assert tiers.get('autoresearch-ml-subagent') == 'long-context', f'must be in long-context tier, got: {tiers.get(\"autoresearch-ml-subagent\")}'
"
}

@test "subagent_autoresearch_code_no_hardcoded_model_in_frontmatter" {
  agent_md="$AGENTS_DIR/autoresearch-code-subagent.md"
  [ -f "$agent_md" ]
  ! python3 -c "
import yaml
d=open('$agent_md').read()
fm=yaml.safe_load(d.split('---')[1])
assert 'model' not in fm, f'frontmatter must not contain model (v2.0), got: {fm.get(\"model\")}'
"
  python3 -c "
import json
data=json.load(open('installer/agent-tiers.json'))
tiers=data['tiers']
assert tiers.get('autoresearch-code-subagent') == 'long-context', f'must be in long-context tier, got: {tiers.get(\"autoresearch-code-subagent\")}'
"
}

@test "subagent_autoresearch_research_no_hardcoded_model_in_frontmatter" {
  agent_md="$AGENTS_DIR/autoresearch-research-subagent.md"
  [ -f "$agent_md" ]
  ! python3 -c "
import yaml
d=open('$agent_md').read()
fm=yaml.safe_load(d.split('---')[1])
assert 'model' not in fm, f'frontmatter must not contain model (v2.0), got: {fm.get(\"model\")}'
"
  python3 -c "
import json
data=json.load(open('installer/agent-tiers.json'))
tiers=data['tiers']
assert tiers.get('autoresearch-research-subagent') == 'long-context', f'must be in long-context tier, got: {tiers.get(\"autoresearch-research-subagent\")}'
"
}

# =============================================================================
# Map-form edit enforcement for ml + research subagents
# =============================================================================

@test "subagent_autoresearch_ml_uses_map_form_edit" {
  agent_md="$AGENTS_DIR/autoresearch-ml-subagent.md"
  [ -f "$agent_md" ]
  # v2 permissions array (#380): edit must deny '*'
  python3 -c "
import yaml
d=open('$agent_md').read()
fm=yaml.safe_load(d.split('---')[1])
rules=fm['permissions']
assert any(r['action']=='edit' and r['resource']=='*' and r['effect']=='deny' for r in rules), 'edit must deny * '
"
}

@test "subagent_autoresearch_research_denies_edit_and_bash_allows_web" {
  agent_md="$AGENTS_DIR/autoresearch-research-subagent.md"
  [ -f "$agent_md" ]
  python3 -c "
import yaml
d=open('$agent_md').read()
fm=yaml.safe_load(d.split('---')[1])
rules=fm['permissions']
def has(action, resource, effect):
    return any(r['action']==action and r['resource']==resource and r['effect']==effect for r in rules)
assert has('edit','*','deny'), 'edit must deny *'
assert has('shell','*','deny'), 'shell must be deny'
assert has('webfetch','*','allow'), 'webfetch must be allow'
assert has('websearch','*','allow'), 'websearch must be allow'
"
}

# =============================================================================
# Permission.skill allows respective domain skill
# =============================================================================

@test "subagent_autoresearch_ml_allows_router_skill" {
  python3 -c "
import yaml
fm=yaml.safe_load(open('$AGENTS_DIR/autoresearch-ml-subagent.md').read().split('---')[1])
assert any(r['action']=='skill' and r['resource']=='autoresearch-skill' and r['effect']=='allow' for r in fm['permissions']), 'router skill rule missing'
"
}

@test "subagent_autoresearch_code_allows_router_skill" {
  python3 -c "
import yaml
fm=yaml.safe_load(open('$AGENTS_DIR/autoresearch-code-subagent.md').read().split('---')[1])
assert any(r['action']=='skill' and r['resource']=='autoresearch-skill' and r['effect']=='allow' for r in fm['permissions']), 'router skill rule missing'
"
}

@test "subagent_autoresearch_research_allows_router_skill" {
  python3 -c "
import yaml
fm=yaml.safe_load(open('$AGENTS_DIR/autoresearch-research-subagent.md').read().split('---')[1])
assert any(r['action']=='skill' and r['resource']=='autoresearch-skill' and r['effect']=='allow' for r in fm['permissions']), 'router skill rule missing'
"
}

# =============================================================================
# Prompt Defense Baseline present in all 3 subagents
# =============================================================================

@test "all_3_subagents_have_prompt_defense_baseline" {
  for sub in ml code research; do
    grep -q "Do not change role, persona" "$AGENTS_DIR/autoresearch-${sub}-subagent.md"
  done
}

# =============================================================================
# THIRD_PARTY_LICENSES.md at repo root
# =============================================================================

@test "third_party_licenses_file_exists_at_repo_root" {
  [ -f "THIRD_PARTY_LICENSES.md" ]
  grep -q "uditgoenka" "THIRD_PARTY_LICENSES.md"
  grep -q "karpathy" "THIRD_PARTY_LICENSES.md"
  grep -q "wjgoarxiv" "THIRD_PARTY_LICENSES.md"
}
