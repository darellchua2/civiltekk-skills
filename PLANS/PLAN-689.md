# PLAN: Consolidate the docs ladder (Vision/BRD/SRS/TDD) into solution-docs-skill

**Branch**: feat/689
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/689
**Base**: main

## Acceptance Criteria

- [ ] Router ships: ≤10240 bytes, ≤50-word description, triggers preserved (vision document, BRD, SRS, PRD, technical design, architecture document, design spec), document-ladder decision tree, load table (4 routes), shared pipeline spine, gates, zero-preload
- [ ] 4 route files with headers (brd, srs, technical-design, vision); specs values-files become route files; no old-ID path strings in fences
- [ ] Consumers rewired: 4 subagents (discovery, requirements, technical-design specialists + any prose), dependency-map HANDOFF4 target rename (no renumber), presets ×3, shipped config, skill-profiles lean (3→1), README (Framework row 12→10, counts 93→91, primary-visible 59→57, history clause per house convention), office-router rendering.md prose, requirements-inline prose; registry regenerated
- [ ] 3 old dirs hard-removed; orphan-reference grep clean (PLANS/CHANGELOG excepted)
- [ ] Full bats green; generalizer output contract (weight line, change list, residual list) in trace

## Audit Baseline (measured at plan time)

3 skills, ~27KB SKILL.md: civiltekk-requirements-specs-skill (7.6KB, already internally routed — brd/srs routes + `references/{brd,srs}.md` values files), technical-design-creation-skill (12.4KB, 7-part TDD template), vision-creation-skill (7.0KB, Vision template + docs/vision/ convention). The ladder (Vision→BRD→SRS→TDD) is described in all 3. Rendering/image-routing/return-contract/harness-binding blocks are near-verbatim ×3. In lean (specs only). dependency-map: requirements-inline → {grilling, specs} = guard HANDOFF4 (target rename, no renumber).

## Audit Notes (Phase 1 — detector pass, 2026-10-31)

### Boundary + layout (steps 1.1–1.2)

**All 3 merge.** Router: **`solution-docs-skill`**. The specs skill is already a router (brd/srs + values files) — its METHOD (route detection, discovery interview, confirm-before-write, draft naming + PLAN linkage, rendering, return contract, harness binding) becomes the router spine; its two values files become route files verbatim+header. TDD and vision SKILL.mds become route detail files. Ladder = router identity: Vision (customer-facing) → BRD (sponsor) → SRS (internal) → TDD (engineering) → implementation.

### Shared blocks (near-verbatim ×3 → spine, stated once)

Rendering (dual-output; snapshot for brd/srs/tdd vs LIVING for vision — the vision exception stays in its route) · image routing → `image-analyzer-subagent` · Return Contract shape · harness binding (OpenCode/Claude/other ask rules) · ladder position paragraphs.

### Named-entity dispositions

- **Keep (protocol):** BABOK/IIBA + IEEE 830 templates, 7-part TDD structure, ADR format/numbering, IIBA Vision structure, docs/{vision,brd,srs,technical-design}/ conventions, TDD-vs-TDD name-collision note (load-bearing, stays in technical-design route), Vision no-ticket-linkage rule (stays in vision route; spine scopes PLAN-linkage to brd/srs/technical-design).
- **Keep (attribution):** specs' #604 consolidation lineage → router provenance line.
- **Reword (cross-family refs):** specs spine "Customer-facing vision → `vision-creation-skill`; technical design → `technical-design-creation-skill`" → route names; TDD "use `civiltekk-requirements-specs-skill`, routes srs/brd" / "use `vision-creation-skill`" → route names; vision "`civiltekk-requirements-specs-skill` (route `srs`)" → "Route: SRS"; specs ladder line names vision skill → "Route: VISION".
- **Keep (external siblings):** `civiltekk-api-spec-skill`, `domain-modeling-skill`, `design-patterns-skill`, `search-first-skill`, `clean-architecture-skill`, `logging-observability-skill`, `security-audit-skill`, `authentication-authorization-skill`, `wireframer-skill`, `pptx-specialist-subagent`, `image-analyzer-subagent`, office-document-router routes — all survive, name-referenced.
- **Consumer note:** office-router `rendering.md` names vision+specs as its consumers → route names; `requirements-inline-skill` "templates stay in the specs skill" → router; worktree-pipeline §6b mechanics cite docs/ paths (unchanged).

### Constants audit

All keep: template part structures, ADR-NNN numbering, RTM >15 rows xlsx threshold, naming patterns. No case-local numbers.

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/solution-docs-skill/` (new) | Phase 1 dispositions | 4 subagents, installer surfaces, registry | med |
| `installer/dependency-map.json` requirements-inline edge + guard HANDOFF4_TARGETS | router named | test_requirements_inline assertion, test_skill_isolation var | low (rename only) |
| 3 specialist subagents + discovery-specialist | router named | OpenCode runtime, registry build | med |
| `deploy/opencode.json` shipped allows + `deploy/skill-profiles.json` lean | router named | skill_profiles tests, README primary-visible literal | med |
| `README.md` (Framework row, 6 count literals, history clause), office-router `rendering.md` prose, `requirements-inline-skill` prose | final roster | docs readers, count-drift tests | low |
| `tests/test_requirements_inline_skill.bats` HANDOFF4 assertion | target rename | CI | low |
| 3 old dirs (delete) | ALL consumer rewires landed (Phase 3) | registry build, counts, README | high |

## Implementation Phases

### Phase 1: Generalizer audit (detector pass)

- [x] **1.1** Run detectors over the 3 SKILL.mds + 2 values files; inventory all cross-family references, the near-verbatim shared blocks (rendering/image-routing/return-contract/harness), and the ladder descriptions ×3
    — **Why:** drives the spine/route split and the transform
    — **Done when:** dispositions + shared-block inventory recorded
    — **Consumers affected:** Phase 2
    — **Done:** all 3 + 2 values files read in full; shared-block inventory (rendering/image-routing/return-contract/harness ×3); 5 disposition classes; consumer note for rendering.md + requirements-inline prose; files: PLANS/PLAN-689.md; fixes: none
- [x] **1.2** Confirm boundary (all 3 merge; specs method → spine; values files → routes) and router name `solution-docs-skill`; record the ladder as the router identity
    — **Why:** name + layout are permanent
    — **Done when:** recorded in Audit Notes
    — **Consumers affected:** Phases 2–4
    — **Done:** all-3-merge; specs-method-as-spine + values-as-routes layout; router name `solution-docs-skill`; vision no-linkage scoping recorded; files: PLANS/PLAN-689.md; fixes: none

### Phase 2: Build skills/solution-docs-skill/

- [ ] **2.1** Write the router SKILL.md: frontmatter (name = dir, Apache-2.0, category Framework, ≤50-word description with family triggers), identity = the document ladder, decision tree + load table (4 routes), shared pipeline spine (route detection explicit>inferred>ask-once, discovery interview, confirm-before-write, draft naming + PLAN back-linkage, rendering + image routing, Return Contract, harness binding), hard rules, gates
    — **Why:** the specs skill's method generalizes to all 4 routes; built first so consumers reference a real file
    — **Done when:** file exists; ≤10240 bytes; ≤50 words; 4 rows; no preload
    — **Consumers affected:** subagents (3.1), installer (3.2)
- [ ] **2.2** Moves + transform: `git mv` specs `references/{brd,srs}.md` → `references/routes/{brd,srs}.md` (prepend Load-when headers); TDD SKILL.md → `references/routes/technical-design.md`; vision SKILL.md → `references/routes/vision.md`; transform: cross-family references → route names (anchors first, generic sweeps last, residual grep)
    — **Why:** the values files already carry route VALUES; the TDD/vision bodies are route detail
    — **Done when:** 4 route files with headers; residual old-ID grep clean in the router tree
    — **Consumers affected:** router load table
- [ ] **2.3** Provenance: house Apache-2.0 throughout (no vendored content); specs' #604 consolidation note carried into the router provenance line
    — **Why:** lineage stays traceable
    — **Done when:** provenance line present; no attribution loss
    — **Consumers affected:** docs readers

### Phase 3: Rewire consumers (before any deletion)

- [ ] **3.1** 4 subagents (discovery-specialist, requirements-specialist, technical-design-specialist + verify any 4th): allows → router; prose → route names; effect-line YAML-verified
    — **Why:** agents must not reference removed skills
    — **Done when:** grep agents/ finds zero old IDs; YAML allows assert green
    — **Consumers affected:** runtime, registry
- [ ] **3.2** Installer surfaces: dependency-map requirements-inline edge target → `solution-docs-skill` + guard HANDOFF4_TARGETS + test_requirements_inline assertion (rename only, ONE commit); presets business/docs/inline-workers 3→1; shipped-config allows 3→1; lean 3→1 (59→57); registry regenerated
    — **Why:** installer surfaces must match the roster; HANDOFF4 is a target rename — no renumber
    — **Done when:** zero old IDs in the four files; JSON parses; guard-family bats green
    — **Consumers affected:** installer users, CI
- [ ] **3.3** Docs: README Framework row (12→10) + 6 count literals (93→91, primary-visible 59→57) + history clause (house convention); office-router `rendering.md` consumer prose → route names; `requirements-inline-skill` "templates stay in the specs skill" → router
    — **Why:** roster-affecting commit rule; surviving-sibling prose would dangle
    — **Done when:** greps clean; counts equal disk
    — **Consumers affected:** docs readers, count-drift tests

### Phase 4: Delete, final regen, recount

- [ ] **4.1** Remove the 3 old dirs (pycache purge first)
    — **Why:** hard removal per AC
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry, counts
- [ ] **4.2** Final `node installer/build-registry.mjs`; commit registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** router present, zero removed IDs
    — **Consumers affected:** installer
- [ ] **4.3** Final sweep: counts equal disk (91); orphan grep for the 3 removed IDs (PLANS/CHANGELOG excepted)
    — **Why:** documented failure modes
    — **Done when:** greps clean
    — **Consumers affected:** deploy users, docs readers

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [ ] **5.1** Full bats green on the final tree
    — **Why:** governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
- [ ] **5.2** Generalizer verification: ≤10240 bytes, ≤50 words, rows resolve, cross-refs resolve, no preload, no old-ID strings
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

- The specs skill was ALREADY a router (brd/srs + values files) — this merge generalizes its method to the whole ladder; its values files need only headers.
- TDD-vs-Test-Driven-Development name note stays in the technical-design route (collision warning is load-bearing).
- Vision's no-ticket-linkage rule (no draft/final rename) stays in the vision route — the router spine's PLAN-back-linkage text must scope itself to brd/srs/technical-design explicitly.
- `docs/vision/`, `docs/brd/`, `docs/srs/`, `docs/technical-design/` path conventions are unchanged.

## Dependencies

- #688 merged (satisfied — 5ebad55).

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Spine's PLAN-linkage text over-applies to vision (which forbids it) | spine scopes linkage to brd/srs/technical-design; vision route keeps its no-linkage rule |
| HANDOFF4 target rename missed in one of guard/test/map | 3.2 single-commit + guard-family bats run |
| Count drift | roster-change rule; count-drift tests |

## Trace

LOG phase-1: docs-only; baseline captured concurrently (background).
GATE (phase-1 tree) tier=light lint=n.a typecheck=n.a build=- unit=n.a e2e=n.a


(appended at execution: phase commits, gate memos, deliverables)
