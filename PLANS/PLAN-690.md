# PLAN: Consolidate 7 code-principle skills into code-principles-skill router

**Branch**: feat/690
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/690
**Base**: main

## Acceptance Criteria

- [ ] Router ships: ≤10240 bytes, ≤50-word description, triggers preserved (clean code, code smells, refactoring, SOLID, design patterns, object design, complexity, clean architecture), decision tree, load table (7 routes), gates, zero-preload
- [ ] 7 route files with headers; the 3 retrofitted routes (clean-code, code-smells, solid-principles) keep their `## Iteration Protocol (opt-in)` sections + protocol citations verbatim; router frontmatter carries `metadata.protocol: autoresearch-opt-in`; no old-ID path strings in fences
- [ ] Consumers rewired: 4 subagents (allows 14→4), init.mjs:917 die() example, presets ×4 (backend/business/inline-workers/review), shipped config 7→1, lean 7→1 (59→53), README (row + counts 91→85 + history clause), 6 sibling-skill citation sites, init.bats fixture (3+ installs), test_autoresearch_protocol tier3 retarget, test_default_behavior retarget, test_installer_versions + test_help_parity verified; registry regenerated
- [ ] 7 old dirs hard-removed; orphan-reference grep clean (PLANS/CHANGELOG excepted)
- [ ] Full bats green; generalizer output contract (weight line, change list, residual list) in trace

## Audit Baseline (measured at plan time)

7 markdown-only skills, 18,186 bytes total (clean-code 5.8K, design-patterns 3.0K, clean-architecture 2.4K, code-smells 2.1K, solid-principles 1.8K, object-design 1.8K, complexity-management 1.4K). All 7 in lean + shipped config. **3 are retrofitted autoresearch skills** (clean-code, code-smells, solid-principles): `## Iteration Protocol (opt-in)` sections + `metadata.protocol: autoresearch-opt-in` + `autoresearch-skill/references/iteration-safety.md` citations — enforced by `test_autoresearch_protocol.bats` tier3 blocks and `test_default_behavior.bats` per-skill assertions. `solid-principles-skill` is init.bats's install-fixture skill (×3+ tests) and init.mjs:917's die() example.

## Audit Notes (Phase 1 — detector pass, 2026-10-31)

### Boundary + retrofit design (steps 1.1–1.2)

**All 7 merge.** Router: **`code-principles-skill`**. Retrofit design: route files keep their `## Iteration Protocol (opt-in)` sections + `autoresearch-skill/references/iteration-safety.md` citations VERBATIM (clean-code ×2 cites, code-smells ×1, solid-principles ×1); router frontmatter carries `metadata.protocol: autoresearch-opt-in`. Routes are loaded one-at-a-time, so per-route loop semantics are unchanged.

### Test-surface inventory (step 1.1)

- `test_autoresearch_protocol.bats` tier3: per-skill section/metadata/citation tests ×3 skills → section+citation retarget to route files, metadata to router.
- `test_default_behavior.bats`: ~17 assertion lines (imperative gating preamble "DO NOT execute any of the following unless" + exactly-once + evaluator-token-in-section-only) for code-smells + solid-principles → retarget to route files.
- `tests/init.bats`: solid-principles install fixture (global ×1, project ×1, target ×1+) → repoint fixture name.
- `test_installer_versions.bats`: --source . install + .skill-source.json + manifest entry (×3 lines) → repoint.
- `test_help_parity.bats`: NO assertion on the die() example (verified) — init.mjs:917 reword is free.

### Named-entity dispositions

- **Keep verbatim:** all principle content (smell catalogs, SOLID rules, pattern applicability tables, complexity heuristics, architecture principles); retrofit sections ×3; the imperative gating preamble (exactly-once constraint is test-enforced).
- **Reword (siblings citing the 7):** architecture-review backing-axis lines (×3+), eval-harness signals line, ponytail-audit, react-quality, python-backend reference, solution-docs technical-design route (×2) → `code-principles-skill` route `<id>`.
- **No anecdotes/constants needing disposition** — the bodies are already rule-form reference material.

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/code-principles-skill/` (new) | Phase 1 dispositions | 4 subagents, installer surfaces, registry, 6 sibling citations | med |
| Router frontmatter `metadata.protocol` + 3 retrofit route sections | autoresearch-skill references (cited, not required) | test_autoresearch_protocol tier3, test_default_behavior | med |
| `installer/init.mjs:917` example (+ parity check) + `tests/init.bats` fixture | router named | installer help/install tests | med |
| 4 presets + shipped config + lean | router named | preset users, skill_profiles tests | med |
| 4 subagents | router named | runtime, registry build | med |
| 6 sibling skills citing the 7 (architecture-review, ponytail-audit, react-quality, python-backend ref, eval-harness, solution-docs technical-design route) | router named | their readers | low |
| `README.md` (Framework row, counts, history clause) | final roster | count-drift tests | low |
| 7 old dirs (delete) | ALL rewires landed | registry, counts | high |

## Implementation Phases

### Phase 1: Generalizer audit (detector pass)

- [x] **1.1** Run detectors over the 7 SKILL.mds; inventory the retrofit sections (3 skills), the sibling citation sites (6 files, exact lines), the test assertion surfaces (autoresearch_protocol tier3, default_behavior blocks, init.bats fixture, installer_versions, help_parity)
    — **Why:** the retrofit carry-over and the fixture repoint are this ticket's correctness conditions
    — **Done when:** dispositions + complete test-surface inventory recorded
    — **Consumers affected:** Phases 2–3
    — **Done:** all 7 read; retrofit inventory (3 skills, sections+cites counted); test-surface inventory complete (5 test files with exact assertion shapes); sibling citation sites listed; files: PLANS/PLAN-690.md; fixes: none
- [x] **1.2** Confirm boundary (all 7 merge) + retrofit design (route files keep sections verbatim; router frontmatter carries the opt-in marker) + router name `code-principles-skill`
    — **Why:** the retrofit design must be fixed before the transform
    — **Done when:** recorded in Audit Notes
    — **Consumers affected:** Phases 2–3
    — **Done:** all-7-merge; retrofit design recorded (route-verbatim + router metadata); name `code-principles-skill`; files: PLANS/PLAN-690.md; fixes: none

### Phase 2: Build skills/code-principles-skill/

- [ ] **2.1** Write the router SKILL.md: frontmatter (name = dir, Apache-2.0, `metadata.protocol: autoresearch-opt-in`, category Code Quality, ≤50-word description with family triggers), identity, decision tree by question type, load table (7 routes), gates (zero-preload; the retrofit opt-in note)
    — **Why:** contract first
    — **Done when:** file exists; ≤10240 bytes; ≤50 words; 7 rows; no preload
    — **Consumers affected:** subagents (3.1), installer (3.2)
- [ ] **2.2** Moves + transform: `git mv` all 7 SKILL.mds → `references/routes/<id>.md`; strip frontmatter; prepend Load-when/Skip-when headers; KEEP the 3 retrofit sections + citations verbatim; residual grep
    — **Why:** the bodies are the value; the retrofit sections are test-enforced content
    — **Done when:** 7 route files with headers; retrofit sections intact ×3; residual clean
    — **Consumers affected:** load table, 3.3 test retargets
- [ ] **2.3** Provenance: house Apache-2.0; no vendored content
    — **Why:** lineage
    — **Done when:** noted
    — **Consumers affected:** docs readers

### Phase 3: Rewire consumers (before any deletion)

- [ ] **3.1** 4 subagents: allows 14→4 (router); prose → route names; YAML-verified
    — **Why:** agents must not reference removed skills
    — **Done when:** grep agents/ clean; YAML asserts green
    — **Consumers affected:** runtime, registry
- [ ] **3.2** Installer surfaces: init.mjs:917 example → router (+ parity assertion if present, same commit); presets backend/business/inline-workers/review → router (dedupe); shipped config 7→1; lean 7→1 (59→53); registry regenerated
    — **Why:** roster-affecting rule
    — **Done when:** zero old IDs in the five files; JSON parses
    — **Consumers affected:** installer users, CI
- [ ] **3.3** Test-surface retargets: init.bats fixture `solid-principles-skill` → `code-principles-skill` (all install tests); test_autoresearch_protocol tier3 blocks → route files (section + citation) + router frontmatter (metadata); test_default_behavior per-skill blocks → retarget; test_installer_versions + test_help_parity verified/updated; sibling citations in 6 skills → route names (architecture-review backing axes, eval-harness signals, ponytail-audit, react-quality, python-backend reference, solution-docs technical-design route)
    — **Why:** tests enforce exact paths/names; siblings would dangle
    — **Done when:** all five test files green; sibling grep clean
    — **Consumers affected:** CI, sibling readers
- [ ] **3.4** README: Framework/Code Quality row + 6 count literals (91→85, primary-visible 59→53) + history clause; registry regen if pending
    — **Why:** roster rule
    — **Done when:** counts equal disk; zero old IDs
    — **Consumers affected:** docs readers, count-drift tests

### Phase 4: Delete, final regen, recount

- [ ] **4.1** Remove the 7 old dirs
    — **Why:** hard removal per AC
    — **Done when:** dirs gone
    — **Consumers affected:** registry, counts
- [ ] **4.2** Final regen; commit registry
    — **Why:** generated artifact
    — **Done when:** router present, zero removed IDs
    — **Consumers affected:** installer
- [ ] **4.3** Final sweep: counts equal disk (85); orphan grep (PLANS/CHANGELOG excepted)
    — **Why:** documented failure modes
    — **Done when:** clean
    — **Consumers affected:** deploy users

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [ ] **5.1** Full bats green on the final tree
    — **Why:** governance
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
- [ ] **5.2** Generalizer verification: ≤10240 bytes, ≤50 words, rows resolve, retrofit sections intact, no old-ID strings
    — **Why:** router-pattern correctness
    — **Done when:** checks pass with measurements
    — **Consumers affected:** skill consumers
- [ ] **5.3** Deliverables in trace: weight line, change list, residual list
    — **Why:** ticket AC
    — **Done when:** three blocks present
    — **Consumers affected:** reviewers, ticket close
- [ ] **5.4** Full exit gate + `tier=full` memo for the final implementation SHA
    — **Why:** PR citation
    — **Done when:** memo matches final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)

## Technical Notes

- The retrofit design (route sections verbatim + router-level opt-in metadata) preserves the per-skill semantics: routes are loaded one-at-a-time anyway, so the loop protocol engages per route exactly as before.
- init.bats uses the fixture generically (any real skill) — the repoint is mechanical.
- This is the roster-reduction wave: token savings are marginal (route files = old bodies); the win is 7 rows → 1 + one decision tree.

## Dependencies

- #689 merged (satisfied — 9885d10).

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Retrofit sections lost in transform | 2.2 keeps them verbatim; protocol tier3 tests enforce |
| init.bats fixture repoint misses a spot | grep gate in 3.3 |
| Preset dedupe order | position-preserving replace (3.2 script) |
| Count drift | roster rule; count-drift tests |

## Trace

LOG phase-1: docs-only; no background baseline (in-cycle + final gates authoritative).
GATE (phase-1 tree) tier=light lint=n.a typecheck=n.a build=- unit=n.a e2e=n.a


(appended at execution: phase commits, gate memos, deliverables)
