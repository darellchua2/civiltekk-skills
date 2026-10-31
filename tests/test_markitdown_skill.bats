#!/usr/bin/env bats

# Tests for the markitdown route of office-document-router-skill (PLAN-GIT-264; absorbed #680).
# Verifies skill existence, frontmatter validity, required sections, exact MCP
# tool name reference, agent routing grants, and cross-file skill count
# consistency. Peer to tests/test_mcp_count_consistency.bats (PLAN-GIT-262).

# Route file since #680 (skill absorbed into office-document-router-skill)
SKILL_MD="skills/office-document-router-skill/references/routes/markitdown.md"
AGENTS_DIR="agents"

# Agents that should have an office-document-router-skill: allow in their permission.skill
AGENTS_WITH_SKILL_GRANT=(
  "office-document-router-subagent"
  "documentation-subagent"
  "requirements-specialist-subagent"
  "technical-design-specialist-subagent"
  "discovery-specialist-subagent"
)

# =============================================================================
# Skill existence + frontmatter
# =============================================================================

@test "markitdown_skill_file_exists" {
  [ -f "$SKILL_MD" ]
}

@test "markitdown_skill_frontmatter_parses" {
  # Route files carry a Load-when header instead of frontmatter (#680)
  grep -qF '**Load when:**' "$SKILL_MD"
  grep -qF '**Skip when:**' "$SKILL_MD"
}

@test "markitdown_skill_required_sections_present" {
  for section in "## What this skill does" "## Requirements & Honesty Note" \
                 "## opencode.json Configuration" "## Available MCP Tools" \
                 "## Format Coverage" "## Decision Tree" "## Usage Patterns" \
                 "## Troubleshooting" "## Fallback Strategy (No MCP)" \
                 "## Privacy Guarantees"; do
    grep -qF "$section" "$SKILL_MD"
  done
}

@test "markitdown_skill_references_exact_tool_name" {
  # The exact MCP tool name must appear in the skill so agents can call it
  grep -q 'convert_to_markdown' "$SKILL_MD"
}

@test "markitdown_skill_decision_tree_covers_pdf_specialist_collision" {
  # Per arch-C2: route must disambiguate markitdown vs the pdf route
  grep -q 'Route: PDF' "$SKILL_MD"
}

# =============================================================================
# Agent routing — 5 agents should grant office-document-router-skill: allow
# =============================================================================

@test "agents_have_markitdown_skill_grant" {
  for agent in "${AGENTS_WITH_SKILL_GRANT[@]}"; do
    echo "  checking $agent" >&3
    python3 -c "
import yaml
fm=yaml.safe_load(open('$AGENTS_DIR/$agent.md').read().split('---')[1])
assert any(r['action']=='skill' and r['resource']=='office-document-router-skill' and r['effect']=='allow' for r in fm['permissions']), 'office-document-router-skill rule missing'
"
  done
}

@test "office_document_primary_agent_has_routing_matrix_row" {
  # Peer-conventional row format (not "Direct MCP call")
  grep -qF 'route `markitdown`' \
    "$AGENTS_DIR/office-document-router-subagent.md"
}

# =============================================================================
# Cross-file skill count consistency (dynamic: count_skills == disk == README)
# =============================================================================

@test "skill_count_consistent_across_docs" {
  # Active count (matches count_skills/Get-SkillCount). BT-157.
  actual=$(find skills -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
  echo "Actual skill count: $actual" >&3

  # setup.sh: dynamic via count_skills() helper — source it, verify output == disk,
  # and confirm no stale hardcoded literal remains. BT-157.
  source <(sed -n '/^count_skills()/,/^}/p' deploy/setup.sh)
  setup_count=$(count_skills skills | tr -d ' ')
  echo "setup.sh count_skills output: $setup_count" >&3
  [ "$setup_count" = "$actual" ]
  ! grep -qE 'SKILLS \([0-9]+\)' deploy/setup.sh

  # setup.ps1 (#474): thin launcher — skill counting lives bash-side
  # (count_skills, verified above); the ps1 performs no selection logic.
  grep -q 'setup.sh' deploy/setup.ps1
  run grep -q 'function Get-SkillCount' deploy/setup.ps1
  [ "$status" -ne 0 ]

  # README.md skill directory count
  readme_count=$(grep -oE '[0-9]+ skill director(y|ies)' README.md | grep -oE '[0-9]+' | head -1)
  echo "README.md count: $readme_count" >&3
  [ "$readme_count" = "$actual" ]
}

@test "configuration_category_count_is_three" {
  # Category counts drift as skills are merged/recategorized (BT-157);
  # README's Configuration count must equal registry.json's.
  actual=$(grep -oE '\*\*Configuration\*\* \([0-9]+\)|Configuration \([0-9]+\)' README.md | grep -oE '[0-9]+' | head -1)
  expected=$(node -e "const r=require('./installer/registry.json'); console.log((r.skills||[]).filter(s=>s.category==='Configuration').length)")
  echo "README.md Configuration count: $actual, registry: $expected" >&3
  [ "$actual" = "$expected" ]
}
