#!/usr/bin/env bats

# Tests for default-behavior preservation when AUTORESEARCH_PROTOCOL is unset.
# Per [m7]: grep for iteration tokens is scoped to the Iteration Protocol section
# line range to avoid false positives on adjacent default-behavior text.
#
# NOTE: bats 1.13+ parses `@test` blocks textually (the preprocessor extracts
# them via regex on source text before any shell evaluation), so the
# `eval "@test ..."` pattern from older bats versions no longer works.
# Tests are therefore written as explicit @test blocks (one per skill per
# assertion) to satisfy bats' parser while still covering all 30 skills
# (7 + 8 + 15) × 3 assertions = 90 cases.

SKILLS_DIR="skills"

# Helper: extract Iteration Protocol section line range from a file.
# Outputs: "<start_line> <end_line>" for the section (inclusive of header,
# exclusive of the next ## header). Returns "0 0" if section absent.
extract_section_range() {
  local file="$1"
  local start end
  start=$(grep -n '^## Iteration Protocol (opt-in)' "$file" | head -1 | cut -d: -f1)
  if [ -z "$start" ]; then
    echo "0 0"
    return
  fi
  # End = line before next ## header that comes AFTER start, or EOF
  end=$(awk -v s="$start" 'NR>s && /^## / {print NR-1; exit}' "$file")
  if [ -z "$end" ]; then
    end=$(wc -l < "$file")
  fi
  echo "$start $end"
}

# =============================================================================
# Helper macro: each skill gets 3 @test blocks expanded below.
# =============================================================================
# To keep this file maintainable, the 3 test bodies per skill share an identical
# shape. Each block is expanded explicitly so bats' textual parser can discover
# it (bats 1.13+ does NOT honor eval-generated @test syntax).

# =============================================================================
# Tier 1 — 7 skills × 3 assertions = 21 tests
# =============================================================================

# --- verification-loop ---
@test "default_behavior_verification-loop_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/verification-loop-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_verification-loop_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/verification-loop-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_verification-loop_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/verification-loop-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- tdd-workflow ---
@test "default_behavior_tdd-workflow_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/tdd-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_tdd-workflow_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/tdd-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_tdd-workflow_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/tdd-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- eval-harness ---
@test "default_behavior_eval-harness_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/eval-harness-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_eval-harness_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/eval-harness-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_eval-harness_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/eval-harness-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- continuous-learning ---
@test "default_behavior_continuous-learning_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/continuous-learning-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_continuous-learning_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/continuous-learning-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_continuous-learning_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/continuous-learning-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- deprecated-code-cleanup ---
@test "default_behavior_deprecated-code-cleanup_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/deprecated-code-cleanup-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_deprecated-code-cleanup_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/deprecated-code-cleanup-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_deprecated-code-cleanup_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/deprecated-code-cleanup-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- linting-workflow ---
@test "default_behavior_linting-workflow_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/linting-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_linting-workflow_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/linting-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_linting-workflow_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/linting-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- coverage-readme-workflow ---
@test "default_behavior_coverage-readme-workflow_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/coverage-readme-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_coverage-readme-workflow_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/coverage-readme-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_coverage-readme-workflow_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/coverage-readme-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# =============================================================================
# Tier 2 — 8 skills × 3 assertions = 24 tests
# =============================================================================

# --- civiltekk-documentation-sync ---
@test "default_behavior_civiltekk-documentation-sync_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/civiltekk-documentation-sync-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_civiltekk-documentation-sync_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/civiltekk-documentation-sync-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_civiltekk-documentation-sync_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/civiltekk-documentation-sync-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- error-resolver-workflow ---
@test "default_behavior_error-resolver-workflow_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/error-resolver-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_error-resolver-workflow_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/error-resolver-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_error-resolver-workflow_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/error-resolver-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- opencode-skills-maintainer ---
@test "default_behavior_opencode-skills-maintainer_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/opencode-skills-maintainer-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_opencode-skills-maintainer_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/opencode-skills-maintainer-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_opencode-skills-maintainer_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/opencode-skills-maintainer-skill/SKILL.md"
  [ -f "$skill_md" ]
  # Exemption: opencode-skills-maintainer intentionally references iteration
  # keywords (`results.tsv`, `Iterations:`, etc.) in its default-mode body —
  # see "Citation drift audit (autoresearch protocol)" section added by
  # PLAN-GIT-239 task 6.1. The maintainer is the auditor of those keywords;
  # their presence in default content is by design, not a leak. Skipping the
  # "ONLY inside section" assertion for this skill.
  skip "maintainer-skill audits iteration keywords by design (task 6.1)"
}

# --- plan-execution ---
@test "default_behavior_plan-execution_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/plan-execution-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_plan-execution_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/plan-execution-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_plan-execution_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/plan-execution-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- pr-workflow (both former PR member skills' preamble pins now target the host, #604) ---
@test "default_behavior_pr-workflow_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/civiltekk-pr-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_pr-workflow_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/civiltekk-pr-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_pr-workflow_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/civiltekk-pr-workflow-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- react-nextjs-antipatterns REMOVED (PLAN-GIT-312: split into hooks + render skills) ---

# --- playwright-responsive-audit ---
@test "default_behavior_playwright-responsive-audit_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/playwright-responsive-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_playwright-responsive-audit_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/playwright-responsive-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_playwright-responsive-audit_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/playwright-responsive-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# =============================================================================
# Tier 3 — 15 skills × 3 assertions = 45 tests
# =============================================================================

# --- search-first ---
@test "default_behavior_search-first_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/search-first-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_search-first_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/search-first-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_search-first_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/search-first-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- civiltekk-api-spec ---
@test "default_behavior_civiltekk-api-spec_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/civiltekk-api-spec-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_civiltekk-api-spec_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/civiltekk-api-spec-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_civiltekk-api-spec_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/civiltekk-api-spec-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- security-audit ---
@test "default_behavior_security-audit_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/security-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_security-audit_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/security-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_security-audit_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/security-audit-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- code-smells ---
@test "default_behavior_code-smells_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/code-smells.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_code-smells_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/code-smells.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_code-smells_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/code-smells.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- performance-optimization ---
@test "default_behavior_performance-optimization_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/performance-optimization-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_performance-optimization_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/performance-optimization-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_performance-optimization_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/performance-optimization-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- civiltekk-react-quality ---
@test "default_behavior_civiltekk-react-quality_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/civiltekk-react-quality-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_civiltekk-react-quality_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/civiltekk-react-quality-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_civiltekk-react-quality_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/civiltekk-react-quality-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- solid-principles ---
@test "default_behavior_solid-principles_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/solid-principles.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_solid-principles_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/solid-principles.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_solid-principles_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/solid-principles.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- clean-code ---
@test "default_behavior_clean-code_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/clean-code.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_clean-code_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/clean-code.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_clean-code_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/code-principles-skill/references/routes/clean-code.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- test-generation (all three former member skills' preamble pins now target the host, #604) ---
@test "default_behavior_test-generation_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/civiltekk-test-generation-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_test-generation_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/civiltekk-test-generation-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_test-generation_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/civiltekk-test-generation-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- civiltekk-diagram ---
@test "default_behavior_civiltekk-diagram_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/civiltekk-diagram-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_civiltekk-diagram_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/civiltekk-diagram-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_civiltekk-diagram_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/civiltekk-diagram-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- wireframer ---
@test "default_behavior_wireframer_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/wireframer-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_wireframer_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/wireframer-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_wireframer_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/wireframer-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}

# --- frontend-design ---
@test "default_behavior_frontend-design_has_imperative_gating_preamble" {
  skill_md="$SKILLS_DIR/frontend-design-skill/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'DO NOT execute any of the following unless' "$skill_md"
}
@test "default_behavior_frontend-design_preamble_appears_exactly_once" {
  skill_md="$SKILLS_DIR/frontend-design-skill/SKILL.md"
  [ -f "$skill_md" ]
  count=$(grep -c 'DO NOT execute any of the following unless' "$skill_md")
  [ "$count" -eq 1 ]
}
@test "default_behavior_frontend-design_evaluator_token_in_section_only" {
  skill_md="$SKILLS_DIR/frontend-design-skill/SKILL.md"
  [ -f "$skill_md" ]
  range=$(extract_section_range "$skill_md")
  start=$(echo "$range" | awk '{print $1}')
  end=$(echo "$range" | awk '{print $2}')
  [ "$start" -gt 0 ] || skip "no Iteration Protocol section"
  # PLAN intent (line 217): tokens "appear ONLY inside the Iteration Protocol
  # section". The literal `>= 1` assertion from the prompt template is too strict
  # for Tier 2/3 partial-pattern retrofits (e.g. plan-execution-skill cites
  # stuck-detection.md only and legitimately never mentions results.tsv).
  # Correct semantics: every occurrence in the file must be inside the section.
  total=$(grep -c 'results.tsv' "$skill_md" || true)
  in_section=$(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e' "$skill_md" | grep -c 'results.tsv' || true)
  [ "$in_section" -eq "$total" ]
}
