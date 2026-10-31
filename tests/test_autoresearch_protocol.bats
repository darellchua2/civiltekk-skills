#!/usr/bin/env bats

# Tests for autoresearch iteration protocol retrofit integrity.
# Covers all skills retrofitted in Phases 3-5 (Tier 1 + Tier 2 + Tier 3).
#
# NOTE: bats 1.13+ parses `@test` blocks textually (the preprocessor extracts
# them via regex on source text before any shell evaluation), so the
# `eval "@test ..."` pattern from older bats versions no longer works.
# Tests are therefore written as explicit @test blocks (one per skill per
# assertion) to satisfy bats' parser while still covering all 30 skills
# (7 + 8 + 15) × 3 assertions + 1 reference-existence test = 91 cases.

SKILLS_DIR="skills"
CORE_REFS_DIR="$SKILLS_DIR/autoresearch-skill/references"

# =============================================================================
# Tier 1: full loop pattern — 7 skills × 3 assertions = 21 tests
# Each Tier 1 skill must cite ALL 5 references.
# =============================================================================

# --- verification-loop ---
@test "tier1_verification-loop_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/verification-loop-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier1_verification-loop_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/verification-loop-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier1_verification-loop_cites_all_5_references" {
  skill_md="$SKILLS_DIR/verification-loop-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- tdd-workflow ---
@test "tier1_tdd-workflow_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/tdd-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier1_tdd-workflow_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/tdd-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier1_tdd-workflow_cites_all_5_references" {
  skill_md="$SKILLS_DIR/tdd-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- eval-harness ---
@test "tier1_eval-harness_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/eval-harness-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier1_eval-harness_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/eval-harness-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier1_eval-harness_cites_all_5_references" {
  skill_md="$SKILLS_DIR/eval-harness-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- continuous-learning ---
@test "tier1_continuous-learning_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/continuous-learning-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier1_continuous-learning_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/continuous-learning-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier1_continuous-learning_cites_all_5_references" {
  skill_md="$SKILLS_DIR/continuous-learning-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- deprecated-code-cleanup ---
@test "tier1_deprecated-code-cleanup_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/deprecated-code-cleanup-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier1_deprecated-code-cleanup_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/deprecated-code-cleanup-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier1_deprecated-code-cleanup_cites_all_5_references" {
  skill_md="$SKILLS_DIR/deprecated-code-cleanup-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- linting-workflow ---
@test "tier1_linting-workflow_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/linting-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier1_linting-workflow_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/linting-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier1_linting-workflow_cites_all_5_references" {
  skill_md="$SKILLS_DIR/linting-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- coverage-readme-workflow ---
@test "tier1_coverage-readme-workflow_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/coverage-readme-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier1_coverage-readme-workflow_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/coverage-readme-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier1_coverage-readme-workflow_cites_all_5_references" {
  skill_md="$SKILLS_DIR/coverage-readme-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# =============================================================================
# Tier 2: partial pattern — 8 skills × 3 assertions = 24 tests
# Each Tier 2 skill cites a SPECIFIC subset of references (not all 5).
# =============================================================================

# --- civiltekk-documentation-sync (audit-trail + crash-recovery) ---
@test "tier2_civiltekk-documentation-sync_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/civiltekk-documentation-sync-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier2_civiltekk-documentation-sync_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/civiltekk-documentation-sync-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier2_civiltekk-documentation-sync_cites_expected_references" {
  skill_md="$SKILLS_DIR/civiltekk-documentation-sync-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in audit-trail crash-recovery; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- error-resolver-workflow (evaluator-contract) ---
@test "tier2_error-resolver-workflow_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/error-resolver-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier2_error-resolver-workflow_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/error-resolver-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier2_error-resolver-workflow_cites_expected_references" {
  skill_md="$SKILLS_DIR/error-resolver-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- opencode-skills-maintainer (evaluator-contract + stuck-detection) ---
@test "tier2_opencode-skills-maintainer_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/opencode-skills-maintainer-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier2_opencode-skills-maintainer_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/opencode-skills-maintainer-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier2_opencode-skills-maintainer_cites_expected_references" {
  skill_md="$SKILLS_DIR/opencode-skills-maintainer-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract stuck-detection; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- plan-execution (stuck-detection) ---
@test "tier2_plan-execution_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/plan-execution-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier2_plan-execution_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/plan-execution-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier2_plan-execution_cites_expected_references" {
  skill_md="$SKILLS_DIR/plan-execution-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in stuck-detection; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- pr-workflow (both former PR member skills' protocol obligations now in the host, #604) ---
@test "tier2_pr-workflow_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/civiltekk-pr-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier2_pr-workflow_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/civiltekk-pr-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier2_pr-workflow_cites_expected_references" {
  skill_md="$SKILLS_DIR/civiltekk-pr-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in evaluator-contract crash-recovery; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# --- react-nextjs-antipatterns REMOVED (PLAN-GIT-312: split into hooks + render skills) ---

# --- playwright-responsive-audit (audit-trail + evaluator-contract) ---
@test "tier2_playwright-responsive-audit_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/playwright-responsive-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier2_playwright-responsive-audit_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/playwright-responsive-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier2_playwright-responsive-audit_cites_expected_references" {
  skill_md="$SKILLS_DIR/playwright-responsive-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  for ref in audit-trail evaluator-contract; do
    grep -q "autoresearch-skill/references/${ref}.md" "$skill_md"
  done
}

# =============================================================================
# Tier 3: light treatment — 15 skills × 3 assertions = 45 tests
# Each Tier 3 skill cites ONLY iteration-safety.md.
# =============================================================================

# --- search-first ---
@test "tier3_search-first_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/search-first-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_search-first_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/search-first-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_search-first_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/search-first-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- civiltekk-api-spec ---
@test "tier3_civiltekk-api-spec_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/civiltekk-api-spec-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_civiltekk-api-spec_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/civiltekk-api-spec-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_civiltekk-api-spec_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/civiltekk-api-spec-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- security-audit ---
@test "tier3_security-audit_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/security-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_security-audit_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/security-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_security-audit_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/security-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- code-smells ---
@test "tier3_code-smells_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/code-smells.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_code-smells_has_opt_in_metadata" {
  # #690: opt-in marker moved to the router frontmatter
  skill_md="$SKILLS_DIR/code-principles-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_code-smells_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/code-smells.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- performance-optimization ---
@test "tier3_performance-optimization_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/performance-optimization-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_performance-optimization_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/performance-optimization-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_performance-optimization_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/performance-optimization-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- civiltekk-react-quality ---
@test "tier3_civiltekk-react-quality_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/civiltekk-react-quality-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_civiltekk-react-quality_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/civiltekk-react-quality-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_civiltekk-react-quality_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/civiltekk-react-quality-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- solid-principles ---
@test "tier3_solid-principles_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/solid-principles.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_solid-principles_has_opt_in_metadata" {
  # #690: opt-in marker moved to the router frontmatter
  skill_md="$SKILLS_DIR/code-principles-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_solid-principles_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/solid-principles.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- clean-code ---
@test "tier3_clean-code_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/clean-code.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_clean-code_has_opt_in_metadata" {
  # #690: opt-in marker moved to the router frontmatter
  skill_md="$SKILLS_DIR/code-principles-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_clean-code_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/clean-code.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- test-generation (all three former member skills' protocol obligations now in the host, #604) ---
@test "tier3_test-generation_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/civiltekk-test-generation-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_test-generation_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/civiltekk-test-generation-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_test-generation_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/civiltekk-test-generation-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- civiltekk-diagram ---
@test "tier3_civiltekk-diagram_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/civiltekk-diagram-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_civiltekk-diagram_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/civiltekk-diagram-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_civiltekk-diagram_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/civiltekk-diagram-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- wireframer ---
@test "tier3_wireframer_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/wireframer-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_wireframer_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/wireframer-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_wireframer_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/wireframer-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# --- frontend-design ---
@test "tier3_frontend-design_has_iteration_protocol_section" {
  skill_md="$SKILLS_DIR/frontend-design-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q '^## Iteration Protocol (opt-in)' "$skill_md"
}
@test "tier3_frontend-design_has_opt_in_metadata" {
  skill_md="$SKILLS_DIR/frontend-design-skill/SKILL.md"
  [ -f "$skill_md" ]
  python3 -c "import yaml; d=open('$skill_md').read(); fm=yaml.safe_load(d.split('---')[1]); assert fm['metadata'].get('protocol')=='autoresearch-opt-in'"
}
@test "tier3_frontend-design_cites_iteration_safety" {
  skill_md="$SKILLS_DIR/frontend-design-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'autoresearch-skill/references/iteration-safety.md' "$skill_md"
}

# =============================================================================
# Reference file existence (all 5 references must exist)
# =============================================================================
@test "all_5_core_references_exist" {
  for ref in evaluator-contract stuck-detection audit-trail crash-recovery iteration-safety; do
    [ -f "$CORE_REFS_DIR/${ref}.md" ]
  done
}
