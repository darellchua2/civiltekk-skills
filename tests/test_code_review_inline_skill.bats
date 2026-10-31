#!/usr/bin/env bats

# code-review-inline-skill contract guard (#635).
# The skill is a thin wrapper whose authority is the deployed agent file;
# these pins hold the wrapper thin — checklist never duplicated, no-subagent
# pin, stop-on-unresolvable — and the wiring (map edge <-> HANDOFF3 invariant,
# preset membership, lean visibility, runtime allow rule).

SKILL_MD="skills/code-review-inline-skill/SKILL.md"

@test "cr_inline: frontmatter contract (name==dir, license, category, mirrors)" {
    [ -f "$SKILL_MD" ]
    grep -q '^name: code-review-inline-skill$' "$SKILL_MD"
    grep -q '^license: Apache-2.0$' "$SKILL_MD"
    grep -q '^category: Code Quality$' "$SKILL_MD"
    grep -q 'mirrors: code-review-subagent' "$SKILL_MD"
}

@test "cr_inline: body pins the no-subagent rule" {
    grep -q "Do NOT delegate the review" "$SKILL_MD"
}

@test "cr_inline: body pins stop-on-unresolvable checklist" {
    grep -q "review unavailable" "$SKILL_MD"
    grep -q "never spawn a subagent" "$SKILL_MD"
}

@test "cr_inline: baseline-first and re-gate citation present" {
    grep -q "reviewer-baseline-skill" "$SKILL_MD"
    grep -q "verification-loop-skill" "$SKILL_MD"
    grep -q "tier=full" "$SKILL_MD"
}

@test "cr_inline: no Docker dead-letter agent path" {
    run grep -c "app/.opencode/agents" "$SKILL_MD"
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}

@test "cr_inline: dependency-map edge mirrors guard HANDOFF3" {
    run node -e "
    const m = require('./installer/dependency-map.json').requiresSkills;
    const edge = m['code-review-inline-skill'] || [];
    const want = ['reviewer-baseline-skill', 'language-review-checklists-skill'];
    if (want.some(w => !edge.includes(w))) process.exit(1);
    "
    [ "$status" -eq 0 ]
    grep -q 'HANDOFF3_OWNER="code-review-inline-skill"' tests/test_skill_isolation.bats
    grep -q 'HANDOFF3_TARGETS="reviewer-baseline-skill language-review-checklists-skill"' tests/test_skill_isolation.bats
}

@test "cr_inline: pack-inline-workers membership + description" {
    run node -e "
    const p = require('./installer/presets/pack-inline-workers.json');
    if (!p.skills.includes('code-review-inline-skill')) process.exit(1);
    if (!p.description.includes('code-review-inline-skill')) process.exit(1);
    "
    [ "$status" -eq 0 ]
}

@test "cr_inline: lean profile + runtime allow rule" {
    run node -e "
    const lean = require('./deploy/skill-profiles.json').lean;
    const rules = require('./deploy/opencode.json').permissions;
    if (!lean.includes('code-review-inline-skill')) process.exit(1);
    if (!rules.some(r => r.action === 'skill' && r.resource === 'code-review-inline-skill' && r.effect === 'allow')) process.exit(2);
    "
    [ "$status" -eq 0 ]
}

@test "cr_inline: wrapper stays thin — no checklist duplication" {
    # The severity table / direct-caller gate prose belongs to the agent file;
    # the wrapper must reference, not restate. Rubric table is the marker.
    run grep -c "Qualification" "$SKILL_MD"
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}
