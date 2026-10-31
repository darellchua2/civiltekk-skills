#!/usr/bin/env bats

# requirements-inline-skill contract guard (#641).
# The skill is a thin wrapper: detection tree + invocation loop. Templates
# stay in civiltekk-requirements-specs-skill, conduct in the agent file.
# These pins hold the wrapper thin and the wiring complete (map edge ==
# HANDOFF5 invariant, preset + closure membership, lean visibility, allow
# rule).

SKILL_MD="skills/requirements-inline-skill/SKILL.md"

@test "req_inline: frontmatter contract (name==dir, license, category, mirrors)" {
    [ -f "$SKILL_MD" ]
    grep -q '^name: requirements-inline-skill$' "$SKILL_MD"
    grep -q '^license: Apache-2.0$' "$SKILL_MD"
    grep -q '^category: Planning & Alignment$' "$SKILL_MD"
    grep -q 'mirrors: requirements-specialist-subagent' "$SKILL_MD"
}

@test "req_inline: detection tree pins (skip rule, thin-AC, ambiguity, zero-reviewer)" {
    grep -q "fewer than 3 ACs" "$SKILL_MD"
    grep -q "ambiguity markers" "$SKILL_MD"
    grep -q "Zero-reviewer rule" "$SKILL_MD"
    grep -q "Skip rule (default)" "$SKILL_MD"
}

@test "req_inline: routes pinned (Mode R rounds, Mode A native questioning, gate-not-review)" {
    grep -q "Max 2 relay rounds" "$SKILL_MD"
    grep -q "NOT a" "$SKILL_MD"
    grep -q "Mode A route (in-session drafting)" "$SKILL_MD"
    grep -q "detection gate" "$SKILL_MD"
}

@test "req_inline: no-subagent pin" {
    grep -q "Do NOT delegate requirements work" "$SKILL_MD"
}

@test "req_inline: no Docker dead-letter agent path" {
    run grep -c "app/.opencode/agents" "$SKILL_MD"
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}

@test "req_inline: dependency-map edge mirrors guard HANDOFF5" {
    run node -e "
    const m = require('./installer/dependency-map.json').requiresSkills;
    const edge = m['requirements-inline-skill'] || [];
    const want = ['grilling-skill', 'civiltekk-requirements-specs-skill'];
    if (want.some(w => !edge.includes(w))) process.exit(1);
    "
    [ "$status" -eq 0 ]
    grep -q 'HANDOFF5_OWNER="requirements-inline-skill"' tests/test_skill_isolation.bats
    grep -q 'HANDOFF5_TARGETS="grilling-skill civiltekk-requirements-specs-skill"' tests/test_skill_isolation.bats
}

@test "req_inline: pack-inline-workers membership incl. closure + description" {
    run node -e "
    const p = require('./installer/presets/pack-inline-workers.json');
    for (const s of ['requirements-inline-skill', 'grilling-skill', 'civiltekk-requirements-specs-skill']) {
        if (!p.skills.includes(s)) process.exit(1);
    }
    if (!p.description.includes('requirements-inline-skill')) process.exit(1);
    "
    [ "$status" -eq 0 ]
}

@test "req_inline: lean profile + runtime allow rule" {
    run node -e "
    const lean = require('./deploy/skill-profiles.json').lean;
    const rules = require('./deploy/opencode.json').permissions;
    if (!lean.includes('requirements-inline-skill')) process.exit(1);
    if (!rules.some(r => r.action === 'skill' && r.resource === 'requirements-inline-skill' && r.effect === 'allow')) process.exit(2);
    "
    [ "$status" -eq 0 ]
}

@test "req_inline: wrapper stays thin — no template restatement" {
    # BABOK/IEEE-830 template content belongs to the specs skill, not here.
    run grep -cE "Stakeholder Requirements|Traceability Matrix" "$SKILL_MD"
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}
