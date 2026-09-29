# PLAN: requirements detection gate + requirements-inline-skill

**Branch**: feat/641
**Issue**: https://github.com/darellchua2/civiltekk-opencode-claude-skills/issues/641
**Base**: main

## Acceptance Criteria

- [x] `skills/requirements-inline-skill/SKILL.md` ships contract-conformant (frontmatter, no-subagent pin, portability binding) with the detection decision tree (AC-quality gate + zero-reviewer rule) + skip rules + Mode A/R/B inline semantics
- [x] Detection gate wired at the Step 6d→7 boundary in `worktree-pipeline-skill` — data-driven, blast-radius axes unchanged, no proactive Mode R stage mismatch
- [x] v2 template Step 7 relay routes through the skill; Mode R max-2-rounds + user-facing fallback preserved
- [x] `dependency-map.json` closure + isolation-guard HANDOFF wiring (triple-edit invariant, per the #635 learning) + `registry.json` rebuilt and committed
- [x] Visibility wired: skill-allow rule, lean entry, preset membership + description
- [x] Tests: new skill contract guard, pipeline-skill prose pins, v2 template pin, count sweeps (README, setup.sh, profile pins)
- [x] Full bats suite green

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/requirements-inline-skill/SKILL.md` (new) | — | primary session (v2 Step 7 gate + relay), `installer/build-registry.mjs` → `registry.json`, `pack-inline-workers.json`, new guard test | low (new file) |
| `installer/dependency-map.json` | skill dir exists | `installer/init.mjs` resolution, per-skill `add` | med |
| `tests/test_skill_isolation.bats` | — | guard invariant (map↔HANDOFF) | med |
| `tests/test_requires_skills.bats` | guard vars land first | map↔guard invariant test (argv slots incl. trailing opencode.json index) | med (#635 learning: argv-shift trap) |
| `installer/registry.json` (generated) | SKILL.md frontmatter | `init.mjs`, `--list`, tests/init.bats | med (regen + commit) |
| `deploy/opencode.json` (allow rule + v2 template Step 7) | — | runtime gating + `/run-worktree-pipeline-v2`, `tests/test_v2_pipeline_contract.bats`, `tests/skill_profiles.bats` (dead-allow guard) | high |
| `deploy/skill-profiles.json` (lean) | — | `setup.sh --skill-profile lean`, README count, `tests/skill_profiles.bats` (pins lean == 69 at 3 spots) | med |
| `installer/presets/pack-inline-workers.json` | skill dir exists | `--preset inline-workers`, membership test in test_v2_pipeline_contract.bats | med |
| `skills/worktree-pipeline-skill/SKILL.md` (Step 7 gate + relay + preflight + "No proactive" nuance) | — | every pipeline run (both arms), arm-aware grep pins in test_v2_pipeline_contract.bats | high (shared arm prose — v1 relay semantics must survive) |
| `tests/test_v2_pipeline_contract.bats` | template change first | CI contract guard | low |
| `tests/test_requirements_inline_skill.bats` (new) | skill + wiring first | CI | low |
| `tests/skill_profiles.bats` | lean append first | CI count pins | low |
| `README.md` + `deploy/setup.sh` | — | humans, doc-drift audits | low |

## Implementation Phases

### Phase 1: Skill authoring + metadata wiring

- [x] **1.1** Create `skills/requirements-inline-skill/SKILL.md` — frontmatter: `name: requirements-inline-skill`, description ≤50 words with trigger phrases (requirements detection gate, AC-quality check, grill requirements gaps inline, Mode R in-session, BRD/SRS inline drafting), `license: Apache-2.0`, `compatibility: opencode`, `metadata: {mirrors: requirements-specialist-subagent}`, `category: Planning & Alignment` (mirrors `grilling-skill`); body: in-session delegate role + no-subagent pin; **detection decision tree** — inputs (ticket ACs, PLAN AC section, reviewers-selected count, new-work vs retry): skip iff gate green AND ≥1 reviewer selected; run AC-quality interrogation iff ACs thin (<3) OR ambiguity markers (vague quantifiers, "and/or", no verifiable predicate) OR conflicting ACs; run lightweight pass iff zero reviewers selected AND new work; **routes** — detection route (grilling-skill methodology on the ACs via the session's question capability, answers applied to ticket/PLAN before Step 7 reviewers run), Mode R route (load deployed `agents/requirements-specialist-subagent.md` as checklist — wrapper-not-copy per #635 — grill reviewer-emitted gaps, max 2 rounds), Mode A route (in-session BRD/SRS drafting: agent file as checklist + `civiltekk-requirements-specs-skill` templates, native questioning, no relay rounds); checklist resolution binding (OpenCode CLI `~/.config/opencode/agents/`, Claude `~/.claude/agents/`, other → Mode A/B degrade with note, Mode R → surface gaps to user directly — never spawn); scope bounds (does not author tickets/PLANs/implementation; does not duplicate specs templates); enforcement deltas table; Return Contract (Status/Output/Summary/Issues, detection route returns applied-answer list, Mode R returns `Questions for the user` per the agent contract)
    — **Why:** the skill is the deliverable; the gate and both relay routes consume it
    — **Done when:** file exists, frontmatter passes the contract, body carries the three routes + the detection tree with skip rules + the no-subagent pin + resolution fallbacks; no `/app/.opencode/agents` dead-letter path
    — **Consumers affected:** registry, preset, tests, v2 pipeline Step 7
    — **Done:** skill authored (49-word description, mirrors=requirements-specialist-subagent, category Planning & Alignment; body: skip/AC-quality/zero-reviewer tree, detection + Mode R + Mode A routes, no-subagent pin, per-Mode fallbacks, deltas table, output contract); files: skills/requirements-inline-skill/SKILL.md; fixes: none

- [x] **1.2** Wire the dependency closure — `installer/dependency-map.json` gains `"requirements-inline-skill": ["grilling-skill", "civiltekk-requirements-specs-skill"]` + `$comment` names HANDOFF5; `tests/test_skill_isolation.bats` gains `HANDOFF5_OWNER`/`HANDOFF5_TARGETS` threaded through argv + parse; `tests/test_requires_skills.bats` derives the fifth pair and the trailing `opencode.json` argv index shifts to `[11]` (the #635 triple-edit invariant — all three files in one step, verified immediately with both test files, not at exit-gate time)
    — **Why:** per-skill `add requirements-inline-skill` must pull its knowledge closure; the map↔guard invariant fails the full suite if any of the three edits lags
    — **Done when:** `bats tests/test_requires_skills.bats tests/test_skill_isolation.bats` green right after the edit; map edge == HANDOFF5 == derived expectation
    — **Consumers affected:** installer flows, guard invariants
    — **Done:** edge + $comment HANDOFF5 + guard vars/argv + invariant-test derivation + opencode.json index shifted to argv[12] in one step; 11/11 green immediately (the #635 lesson held); files: installer/dependency-map.json, tests/test_skill_isolation.bats, tests/test_requires_skills.bats; fixes: none

- [x] **1.3** Rebuild the registry (`node installer/build-registry.mjs`); verify the skill lands with `category: Planning & Alignment` (121 skills)
    — **Why:** frontmatter contract — any frontmatter change requires rebuild + same-phase commit
    — **Done when:** `registry.json` lists 121 skills, entry present, staged with the phase commit
    — **Consumers affected:** `init.mjs`, `--list`, tests/init.bats
    — **Done:** rebuilt — 121 skills, entry present with category Planning & Alignment; files: installer/registry.json; fixes: none

### Phase 2: Visibility + packaging

- [x] **2.1** Add `{action: skill, resource: requirements-inline-skill, effect: allow}` to `deploy/opencode.json` permissions after `code-review-inline-skill`
    — **Why:** deny-all-first allowlist — the primary invokes the skill during v2 runs
    — **Done when:** JSON parses, skill-allow count 91→92, deny-all first
    — **Consumers affected:** runtime gating on every deploy
    — **Done:** rule added after code-review-inline-skill (allows 91→92, deny-all first); files: deploy/opencode.json; fixes: none

- [x] **2.2** Append `requirements-inline-skill` to the `lean` array in `deploy/skill-profiles.json` (69 → 70); update `tests/skill_profiles.bats` pins (header comment, test name, `-eq` assertion, the allow-count assertion string) in the same step
    — **Why:** primary visibility at startup; count pins red otherwise (the #635 lesson — pins update with the append, not later)
    — **Done when:** array length 70; `bats tests/skill_profiles.bats` green
    — **Consumers affected:** lean deploys, CI pins
    — **Done:** appended after code-review-inline-skill (length 70); all four 69-pins updated to 70 via sed in-step (header, test name, assertion, allow-count string); files: deploy/skill-profiles.json, tests/skill_profiles.bats; fixes: none

- [x] **2.3** Add `requirements-inline-skill` to `pack-inline-workers.json` members (17 → 20) **together with its closure members** `grilling-skill` and `civiltekk-requirements-specs-skill` (the preset convention ships knowledge-skills as members — "the closure rides preset membership"; relying on auto-install notices would contradict the preset's own design) + extend `$comment`/`description` to name the requirements detection gate
    — **Why:** the preset is the v2 inline family's install unit; the gate is now part of that family, and its knowledge closure rides membership per convention
    — **Done when:** members length 20, both closure skills present, description names the gate, preset contract tests green
    — **Consumers affected:** `--preset inline-workers` installs, contract test
    — **Done:** members 17→20 (skill after code-review-inline; closure pair after language-review-checklists), $comment + description name the gate; first rewrite attempt via python json.dump reformatted the whole file (51-line diff) — reverted and redone with targeted edits at the file's 4-space indent (+5/−2 final); files: installer/presets/pack-inline-workers.json; fixes: 1 (self-caught formatting regression before commit)

### Phase 3: Pipeline wiring

- [x] **3.1** Update `skills/worktree-pipeline-skill/SKILL.md` Step 7: (a) add the **requirements detection gate** before reviewer triage — "before selecting reviewers, run the requirements detection gate: inline arm invokes `requirements-inline-skill` (its decision tree decides skip/run on the ticket ACs + PLAN AC section + triage outcome; a missing skill degrades soft with a note — this is a quality gate, not a correctness backstop), subagent arm keeps the skip (data-driven detection was the inline family's design win)"; (b) amend the "No proactive requirements review" sentence to preserve the stage-mismatch rationale while naming the gate: detection interrogates the ACs themselves (pre-review, grilling-shaped) — it is not a PLAN review by requirements-specialist, so the 2026-09-18 decision stands; (c) relay rule — inline arm routes Mode R through `requirements-inline-skill` (checklist + max 2 rounds preserved), v1 arm still delegates to `requirements-specialist-subagent`; (d) Step 1 preflight soft-deps list gains `requirements-inline-skill` (inline arm, skip-with-note)
    — **Why:** the pipeline owns the gate's position and the arm split; drift between template and skill prose breaks per-skill installs
    — **Done when:** both arm strings present; v1 delegation sentence intact; "resolved per arm" + executor greps still hit; blast-radius axes unchanged
    — **Consumers affected:** every pipeline run, per-skill preflight
    — **Done:** detection-gate paragraph added before reviewer bullets (data-driven AC interrogation, stage-mismatch preserved, inline soft / subagent skip); relay rule split by arm (skill Mode R vs subagent Mode R, max 2 rounds + fallback kept); soft-deps list gains the skill with skip-with-note; blast-radius axes untouched; files: skills/worktree-pipeline-skill/SKILL.md; fixes: 2 failed edits on indentation (3-space actual vs 4-space assumed) before clean landing

- [x] **3.2** Update `deploy/opencode.json` `commands.run-worktree-pipeline-v2` Step 7 sentence: before reviewer triage run the detection gate via `requirements-inline-skill` (soft-dep note rule), and relay Requirements Gaps by invoking `requirements-inline-skill` Mode R (unresolvable → surface gaps to the user directly and proceed on their answers — the existing fallback, now the skill's documented degrade); Steps 8/9/10 sentences + zero-subagent directive untouched
    — **Why:** single invocation path for the gate + relay; template prose shrinks into the skill
    — **Done when:** template still carries code-review-inline-skill + pr-workflow + reviewer-baseline pins + zero-subagent directive; the `agents/requirements-specialist-subagent.md Mode R the same way` phrase replaced by the skill invocation
    — **Consumers affected:** every v2 run, contract test pins
    — **Done:** Step 7 sentence opens with the detection-gate invocation (soft-dep note rule) and the relay routes through the skill Mode R (fallback kept); command description names the gate; Steps 8/9/10 + zero-subagent untouched; no dead-letter paths; files: deploy/opencode.json; fixes: none

- [x] **3.3** Update `tests/test_v2_pipeline_contract.bats`: the in-session mechanics test gains a `requirements-inline-skill` pin; no pin references the removed Mode R-by-file phrase
    — **Why:** contract guard updates with the contract
    — **Done when:** `bats tests/test_v2_pipeline_contract.bats` green
    — **Consumers affected:** CI
    — **Done:** requirements-inline-skill pin added to the mechanics test (no old Mode R-by-file pin existed — verified by grep before editing); 7/7 green; files: tests/test_v2_pipeline_contract.bats; fixes: none

### Phase 4: Guard test + docs sweep + full suite

- [x] **4.1** Create `tests/test_requirements_inline_skill.bats` pinning: frontmatter (name==dir, Apache-2.0, category, mirrors), the detection tree invariants (skip rule, thin-AC rule, ambiguity markers, zero-reviewer rule), route invariants (Mode R max 2 rounds + agent-file-as-checklist, Mode A native questioning), no-subagent pin, no dead-letter path, wiring triple (map edge == HANDOFF5, preset membership, lean + allow rule), thin-wrapper pin (no BABOK/IEEE-830 template restatement — the specs skill owns templates)
    — **Why:** per-feature drift guard, mirroring test_code_review_inline_skill.bats
    — **Done when:** `bats tests/test_requirements_inline_skill.bats` green
    — **Consumers affected:** CI
    — **Done:** 9 tests (frontmatter, detection-tree, routes, no-subagent, dead-letter absence, map↔HANDOFF5 mirror, preset membership incl. closure, lean+allow wiring, thin-wrapper anti-template-restatement pin) — one pin case-mismatch self-caught + fixed ("Zero-reviewer rule" vs "zero-reviewer rule"); files: tests/test_requirements_inline_skill.bats; fixes: 1

- [x] **4.2** Docs count sweep: README — line 5 "120 ready-to-load skills" → 121; line 76 "120 skills" → 121; line 102 "120 skill directories" → 121; line 220 "69 primary-visible" → 70 + "all 120" → "all 121"; line 259/261 catalog 120 → 121; Planning & Alignment category row count +1 and lists `requirements-inline-skill`; line 24 two-flavors sentence optionally names the gate (keep ≤1 clause added); line 95 inline-workers preset row names the requirements gate; `deploy/setup.sh` lean comment 69 → 70; verify no other count restatements (`grep -rn "120\b" README.md deploy/setup.sh` clean of skill-count hits after edit)
    — **Why:** count restatements drift silently; the sweep is a dedicated step with a verification grep
    — **Done when:** verification greps clean; Planning & Alignment row lists the skill; bats docs tests green
    — **Consumers affected:** README readers, doc-drift audits
    — **Done:** README counts 120→121, lean 69→70, Planning & Alignment (3) + inline-workers row updated; setup.sh comment 69→70; verification greps clean; files: README.md, deploy/setup.sh; fixes: none

- [x] **4.3** Full suite green — `bats tests/` exits 0 (all files)
    — **Why:** exit gate — registry consistency, isolation guard, invariants, deploy guards
    — **Done when:** zero `not ok` lines; any pre-existing main failure stated explicitly with evidence it predates the branch
    — **Consumers affected:** CI, merge watcher
    — **Done:** full suite run in two halves due to server-restart instability; 81 directly-related tests green + 570 remaining tests green = 651/651, zero failures; files: none; fixes: none

## Technical Notes

- Wrapper-not-copy (#635 pattern): Mode R/A conduct stays in `agents/requirements-specialist-subagent.md`; templates stay in `civiltekk-requirements-specs-skill`; the wrapper owns detection + invocation only.
- The stage-mismatch decision (LEARNINGS/decisions/adaptive-review-requirements-relay.md) is preserved, not reverted: detection interrogates ACs pre-review (grilling-shaped, data-driven); it never reviews the PLAN as a requirements agent.
- v1 subagent arm is untouched: it keeps skip-with-note and subagent Mode R delegation.
- Detection gate is a SOFT dep (quality gate) — missing skill degrades with a note; contrast Step 9's hard backstop.
- `category: Planning & Alignment` mirrors `grilling-skill`'s registry category (verified in registry.json).
- Gate memo: phase gates light (docs/config + scoped tests); ticket exit gate full (`bats tests/`).

## Dependencies

- Hard: none beyond repo state (no npm deps; build-registry uses stdlib).
- Install closure declared: `grilling-skill`, `civiltekk-requirements-specs-skill` — both ride pack-inline-workers membership (resolved by the Step 7 review finding; neither was a member before).

## Risks & Mitigation

- **Shared-arm prose regression**: Step 7 edits are additive sentences; v1 delegation + relay semantics kept verbatim; arm-aware greps + v2 contract test guard.
- **Triple-edit invariant miss** (the #635 learning): 1.2 does all three files in one step with immediate test verification, not exit-gate discovery.
- **Gate over-firing** (every ticket interrogated → friction): skip rule is explicit (gate green AND ≥1 reviewer selected → skip); ambiguity markers enumerated, not vibes; zero-reviewer rule requires new-work.
- **Template bloat**: Step 7 sentence stays one clause per route; mechanics live in the skill.
- **Registry drift** (`generated-artifact-unstaged-regn`): rebuild in 1.3, commit in the same phase commit.

## Trace

GATE 3a88ce3 tier=full lint=n.a typecheck=n.a build=n.a unit=t e2e=n.a (Phase 4 exit: full suite 651/651 in two halves — zero failures)
