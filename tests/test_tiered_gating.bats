#!/usr/bin/env bats

# Tiered verification gating (#488) — pins the light/full gate contract across
# the canonical contract and the deferring surfaces.
# Assertions use case-insensitive or fixed-string greps over the spellings
# actually written (LEARNINGS: case-sensitive-grep-gates-false-green,
# guard-regex-quote-shape-mismatch); format tokens containing `|` use grep -F
# so BRE alternation cannot false-match a partial token.

SKILLS_DIR="skills"

# Helper: extract a ### subsection's line range from a file.
# Outputs "<start> <end>" (inclusive of header, exclusive of the next ##/###
# header). Outputs "0 0" when absent.
extract_subsection_range() {
  local file="$1" header="$2" start end
  start=$(grep -n "^### $header" "$file" | head -1 | cut -d: -f1)
  if [ -z "$start" ]; then
    echo "0 0"
    return
  fi
  end=$(awk -v s="$start" 'NR>s && /^###? / {print NR-1; exit}' "$file")
  if [ -z "$end" ]; then
    end=$(wc -l < "$file")
  fi
  echo "$start $end"
}

VL="$SKILLS_DIR/verification-loop-skill/SKILL.md"

# =============================================================================
# Phase 1 — canonical contract (verification-loop-skill)
# =============================================================================

@test "tier1_gating_verification-loop_has_tiered_gating_subsection" {
  [ -f "$VL" ]
  grep -q '^### Tiered gating' "$VL"
}

@test "tier1_gating_verification-loop_light_gate_default" {
  read -r s e <<< "$(extract_subsection_range "$VL" 'Tiered gating')"
  [ "$s" -gt 0 ]
  sed -n "${s},${e}p" "$VL" | grep -qi 'light gate'
  sed -n "${s},${e}p" "$VL" | grep -qi 'affected tests only'
  sed -n "${s},${e}p" "$VL" | grep -qi 'needs no justification'
}

@test "tier1_gating_verification-loop_escalation_anchors" {
  read -r s e <<< "$(extract_subsection_range "$VL" 'Tiered gating')"
  [ "$s" -gt 0 ]
  sed -n "${s},${e}p" "$VL" | grep -qi 'critical-area anchor'
  sed -n "${s},${e}p" "$VL" | grep -q 'Dependency & Consumer Map'
  sed -n "${s},${e}p" "$VL" | grep -qF 'unsure always escalates to full'
}

@test "tier1_gating_verification-loop_exit_gate_unconditional" {
  read -r s e <<< "$(extract_subsection_range "$VL" 'Tiered gating')"
  [ "$s" -gt 0 ]
  sed -n "${s},${e}p" "$VL" | grep -qi 'ticket exit gate'
  sed -n "${s},${e}p" "$VL" | grep -qi 'unconditionally'
}

@test "tier1_gating_verification-loop_one_directional_escalation" {
  read -r s e <<< "$(extract_subsection_range "$VL" 'Tiered gating')"
  [ "$s" -gt 0 ]
  sed -n "${s},${e}p" "$VL" | grep -qi 'one-directional'
}

@test "tier1_gating_verification-loop_memo_tier_token" {
  grep -qF 'tier=light|full' "$VL"
  grep -qF 'unit=t|-|n.a' "$VL"
}

@test "tier1_gating_verification-loop_full_gate_cross_reference" {
  grep -qiF 'This sequence is the **full gate**' "$VL"
}

@test "tier1_gating_verification-loop_dash_token_gloss" {
  grep -qiF 'An axis skipped **by tier**' "$VL"
  grep -qiF 'build has no `n.a` form' "$VL"
}

@test "tier1_gating_verification-loop_na_gloss_light_only" {
  grep -qF 'unit=n.a' "$VL"
  grep -qiF 'never INCONCLUSIVE' "$VL"
  grep -qiF 'valid only on `tier=light` memos' "$VL"
}

@test "tier1_gating_verification-loop_push_invariant" {
  grep -qi 'push invariant' "$VL"
  grep -qiF 'tier=full` memo' "$VL"
  grep -qiF '**final** pushed SHA' "$VL"
}

@test "tier1_gating_verification-loop_ci_only_unconditional_rerun_unchanged" {
  grep -qF 'only unconditional re-run' "$VL"
}

PE="$SKILLS_DIR/plan-execution-skill/SKILL.md"

# =============================================================================
# Phase 2 — executor integration (plan-execution-skill)
# =============================================================================

@test "tier2_gating_plan-execution_light_gate_default" {
  [ -f "$PE" ]
  grep -qF 'is the per-phase default' "$PE"
}

@test "tier2_gating_plan-execution_exit_gate_full" {
  grep -qiF 'ticket exit gate' "$PE"
  grep -qiF 'runs full unconditionally' "$PE"
}

@test "tier2_gating_plan-execution_memo_tier_token_derived_from_contract" {
  # Derived pin (derived-consistency-pins): PE's memo line must equal VL's
  vl_format=$(grep -oE 'GATE <short-sha> [^`]*' "$VL" | head -1)
  [ -n "$vl_format" ]
  grep -qF "$vl_format" "$PE"
}

@test "tier2_gating_plan-execution_phase_advance_tier_invariant" {
  grep -qF 'applicable gate tier is green' "$PE"
}

@test "tier2_gating_plan-execution_final_push_invariant" {
  grep -qF '**final** pushed SHA of the run' "$PE"
  grep -qiF 'phase evidence' "$PE"
}

@test "tier2_gating_plan-execution_escalation_logging" {
  grep -qiF 'LOG line naming the anchor' "$PE"
}

@test "tier2_gating_plan-execution_never_push_red_unchanged" {
  grep -qF 'Never push red code' "$PE"
}

WP="$SKILLS_DIR/worktree-pipeline-skill/SKILL.md"

# =============================================================================
# Phase 3 — orchestrator integration (worktree-pipeline-skill)
# =============================================================================

@test "tier3_gating_worktree-pipeline_step8_exit_gate_full" {
  [ -f "$WP" ]
  # Newline+indent normalized: the phrase wraps across lines in the markdown
  tr '\n' ' ' < "$WP" | tr -s ' ' | grep -qiF 'ticket exit gate'
  tr '\n' ' ' < "$WP" | tr -s ' ' | grep -qiE 'exit +gate.*is full'
}

@test "tier3_gating_worktree-pipeline_step9_re_gate_rule" {
  grep -qiF 'Re-gate after review fixes' "$WP"
  grep -qiF 'gate once on the fixed tree' "$WP"
}

@test "tier3_gating_worktree-pipeline_step10_tier_full_citation" {
  grep -qF 'GATE <short-sha> tier=full' "$WP"
  grep -qiF 'never satisfies this citation' "$WP"
}

@test "tier3_gating_worktree-pipeline_step9_unconditional_review_unchanged" {
  grep -qF 'Step 9 code review' "$WP"
  grep -qF '(unconditional) backstops' "$WP"
}

PC="$SKILLS_DIR/civiltekk-pr-workflow-skill/references/create.md"

# =============================================================================
# Phase 4 — memo-consumer update (civiltekk-pr-workflow-skill, create route;
# consolidated from the two former PR member skills, #604)
# =============================================================================

@test "tier4_gating_pr-workflow_create_tier_full_memo_check" {
  [ -f "$PC" ]
  grep -qF 'GATE <sha> tier=full' "$PC"
  grep -qiF 'never satisfies this check' "$PC"
}
