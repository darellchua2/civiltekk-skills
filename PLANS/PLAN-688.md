# PLAN: Consolidate 4 autoresearch skills into autoresearch-skill router

**Branch**: feat/688
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/688
**Base**: main

## Acceptance Criteria

- [x] Router ships: ≤10240 bytes, ≤50-word description, triggers preserved (autonomous loop, code optimization, ML training, literature review, keep/revert), decision tree, core protocol as spine, load table (3 routes), gates, zero-preload
- [x] 3 route files with headers; core `references/` at router root; scripts + per-loop templates absorbed; no old-ID path strings in scripts/templates/fenced blocks
- [x] HANDOFF2 (multi-owner autoresearch pair) retired: dependency-map ×3 edges removed + guard renumbered across ALL affected test files in one commit; `grep -rn "HANDOFF" tests/` re-verified post-renumber
- [x] Retrofit citation network repointed: all surviving skills citing `autoresearch-core-skill/references/` (24 files) renamed to `autoresearch-skill/references/`; protocol test expected prefix updated
- [x] 3 loop subagents rewired (router allow); pack-research preset 4→1; README row + count literals (96→93); AGENTS.md prose (exception retired + stale HANDOFF3 mention fixed); THIRD_PARTY §1 paths repointed; old dirs hard-removed; orphan grep clean
- [x] Registry regen + count literals ride roster-affecting commits; full bats green; generalizer output contract (weight line, change list, residual list) in trace

## Audit Baseline (measured at plan time)

4 skills, 21,829 bytes of SKILL.md + 15,132 bytes core `references/*.md` (5 files) + 15,230 bytes core scripts (3) + per-loop `templates/` dirs. Not in lean, not in shipped-config allows. HANDOFF2 = the multi-owner pair (3 owners → core). The core skill is the #602 **shared protocol host**: 24 surviving skills + 5 templates/scripts cite `autoresearch-core-skill/references/*.md` by path (prose citations, NOT installer edges), mechanically enforced by `tests/test_autoresearch_protocol.bats` (`tier1_*_cites_all_5_references` greps the exact prefix per retrofitted skill).

## Audit Notes (Phase 1 — detector pass, 2026-10-31)

### Boundary + layout (steps 1.1–1.2)

**All 4 merge — core becomes the router spine, not a route.** Router: `autoresearch-skill`. Layout: core `references/*.md` (5 protocol deep-dives) → router root `references/`; core `scripts/*` (3) → `scripts/`; loop SKILL.mds → `references/routes/{code,ml,research}.md`; loop `templates/*` → `templates/<loop>/`. **Citation format: skill-root-relative** — route files cite `references/X.md`, `scripts/tool`, `templates/<loop>/file`; the router states the convention once.

### Citation-network inventory (step 1.1 — the dominant surface)

Uniform string `autoresearch-core-skill/references/` appears in **24 surviving skills** (verification-loop ×5, tdd-workflow ×6, eval-harness ×5, linting-workflow ×5, continuous-learning ×6, coverage-readme ×6, deprecated-code-cleanup ×6, opencode-skills-maintainer ×5, plan-execution ×3, civiltekk-pr-workflow ×3, playwright-responsive-audit ×3, civiltekk-documentation-sync ×3, clean-code ×2, + 12 singles) — mechanically enforced by `test_autoresearch_protocol.bats` `tier1_*_cites_all_5_references` (exact-prefix grep ×6 skills × 5 refs). Also citing: 3 loop subagents, 5 templates, 2 core scripts, AGENTS.md, dependency-map, pack-research, README, THIRD_PARTY §1. Rename: `autoresearch-core-skill/references/` → `autoresearch-skill/references/` everywhere + test expected prefix (one commit, 3.2).

### Named-entity dispositions

- **Keep (protocol contracts):** the `{"pass":bool,"score":N}` shape, 5-stage order, 3-strike/5-strike thresholds, 25-iteration default, TSV 8-column spec, val_bpb metric, TIME_BUDGET=5min, Tier 1/2 taxonomy, NEVER STOP/NEVER ASK directives.
- **Keep (attribution):** uditgoenka/karpathy/wjgoarxiv MIT notices — per-route blocks stay (they differ per route).
- **Fold into spine:** core's 5-stage loop, evaluator contract summary, stuck detection, injection boundary, autonomy directive, crash recovery (full detail stays in `references/*.md`, absorbed unchanged).
- **Drop:** core's "When to use me" section (obsolete — the router IS the methodology host now); "Domain skills cite my references by path" self-description → router convention line.
- **Reword (cross-refs):** loop triggers "→ `autoresearch-ml-skill`" → "→ the `ml` route"; loop citations `autoresearch-core-skill/references/X.md` → `references/X.md`; loop templates `autoresearch-<loop>-skill/templates/` → `templates/<loop>/`; core References/Scripts tables → skill-root-relative.

### Constants audit

All keep: thresholds and defaults are the protocol itself. No case-local numbers.

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/autoresearch-skill/` (new) | Phase 1 dispositions | 3 loop subagents, registry, pack-research, retrofit citations (path target) | med |
| Core `references/*.md` (protocol host detail) | router exists | 24 retrofit-citing skills, protocol test, 3 routes | **high** (rename touches 24 files) |
| `installer/dependency-map.json` requiresSkills ×3 + guard HANDOFF2 | removal set final | test_skill_isolation (vars+arity), test_requires_skills (×2 heredocs + per-family), test_code_review_inline (HANDOFF3→2), test_requirements_inline (HANDOFF5→4) | high |
| 3 loop subagents | router named | OpenCode runtime, agent-tiers (names unchanged), registry build | med |
| `tests/test_autoresearch_protocol.bats` (26 refs) + `test_autoresearch_skills.bats` (yaml tests) | citation rename + route layout final | CI | med |
| `tests/test_default_behavior.bats:328` citation-drift audit section | citation rename final | CI | low |
| `installer/presets/pack-research.json` | final roster | installer `--preset research` users | low |
| `README.md` (Autoresearch row + 6 count literals), `AGENTS.md` (exception prose + stale HANDOFF3 mention), `THIRD_PARTY_LICENSES.md` §1 (vendored paths) | final roster | docs readers, count-drift tests, compliance | low |
| 4 old dirs (delete) | ALL consumer rewires landed (Phase 3) | registry build, counts, README | high |

Phase ordering: no deletion (4.1) before every consumer is rewired (Phase 3); registry regen + counts ride roster-affecting commits.

## Implementation Phases

### Phase 1: Generalizer audit (detector pass)

- [x] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 4 SKILL.mds; inventory ALL path citations (`autoresearch-core-skill/references|scripts|templates`) across the 4 members + the 24-skill retrofit network + templates + scripts, with their post-merge forms
    — **Why:** the citation network is this ticket's dominant consumer surface; every path form must be inventoried before the transform
    — **Done when:** zero un-dispositioned entities; citation inventory complete with counts per file
    — **Consumers affected:** Phase 2 transform, Phase 3 rewire
    — **Done:** all 4 read in full; citation inventory complete (24 skills + templates/scripts/tests with counts, uniform string verified); 5 disposition classes recorded; files: PLANS/PLAN-688.md; fixes: none
- [x] **1.2** Confirm boundary (all 4 merge; core becomes spine + shared references) and router layout (references at root, scripts at root, templates per-loop subdir); record the citation-format decision (skill-root-relative) in the layout
    — **Why:** the citation format must be decided once — 24 files depend on it
    — **Done when:** layout + citation format recorded in Audit Notes
    — **Consumers affected:** Phases 2–3
    — **Done:** all-4-merge confirmed; core-as-spine + layout + skill-root-relative citation format recorded; files: PLANS/PLAN-688.md; fixes: none

### Phase 2: Build skills/autoresearch-skill/

- [x] **2.1** Write the router SKILL.md: frontmatter (name `autoresearch-skill`, Apache-2.0, `metadata.protocol: autoresearch-default-on`, category Autoresearch, ≤50-word description with family triggers), identity (mechanical evaluator, no self-judgment), the 5-stage loop + evaluator contract + stuck detection + injection boundary + autonomy directive as the spine (from core), load table (3 routes), references/scripts index, hard rules, gates
    — **Why:** core IS the shared protocol — it becomes the router spine, not a route
    — **Done when:** file exists; ≤10240 bytes; ≤50 words; 3 rows; no preload
    — **Consumers affected:** subagents (3.1), registry, retrofit citations (3.2)
    — **Done:** router written — 5060 bytes, description 34 words, 3 route rows, core's 5-stage loop/evaluator contract/protocol rules/autonomy as spine, references+scripts index, metadata.protocol carried; files: skills/autoresearch-skill/SKILL.md; fixes: none
- [x] **2.2** Moves + transform: `git mv` loop SKILL.mds → `references/routes/{code,ml,research}.md`; core `references/*.md` → router root `references/`; core `scripts/*` → `scripts/`; loop `templates/*` → `templates/<loop>/`; transform route files (headers with Load-when/Skip-when; citation rewrites: `autoresearch-core-skill/references/` → `references/`, `autoresearch-<loop>-skill/templates/` → `templates/<loop>/`; triggers cross-refs → route names; core's obsolete "When to use me" folded into spine). Anchor-specific rewrites before generic sweeps; residual grep for any `autoresearch-` path form
    — **Why:** the moves create the layout the 24-file citation rename targets; mangled anchors are the documented failure mode
    — **Done when:** 3 route files with headers; all absorbed files present; residual old-ID path grep clean
    — **Consumers affected:** 3.2 citation rename target paths
    — **Done:** moves via git mv (3 routes, 5 refs → root, 3 scripts → root, templates per-loop); route transform anchors-first (citations ×14, Load-me ×3, cross-routes ×6, templates ×9); template/script/residue sweep ×12 files; residual old-ID grep clean; files: references/routes/*, references/, scripts/, templates/; fixes: none
- [x] **2.3** Preserve provenance: per-route attribution blocks kept (uditgoenka/karpathy/wjgoarxiv MIT notices); scripts keep executable bits; AST/bash -n syntax checks over absorbed scripts
    — **Why:** vendored MIT attribution and working scripts must survive
    — **Done when:** attribution present per route; `bash -n` clean on .sh, `py_compile` clean on .py
    — **Consumers affected:** compliance readers, script runtime
    — **Done:** per-route attribution blocks intact; bash -n clean ×2; py_compile clean; executable bits preserved (autoresearch-loop.sh +x); files: scripts/; fixes: none

### Phase 3: Rewire consumers (before any deletion)

- [x] **3.1** 3 loop subagents: allow 2→1 (`autoresearch-skill`); prose references → route names; verify effect-line intact (Wave-2 bug class)
    — **Why:** agents must not reference removed skills; YAML assertions in test_autoresearch_skills must stay green
    — **Done when:** grep of the 3 agents finds zero old IDs; YAML allow assertion passes
    — **Consumers affected:** registry build, runtime
    — **Done:** 3 subagents rewired (autoresearch allows 2→1 router each; other skill allows untouched); YAML assertion effect-ok=True ×3; prose refs → route names; files: agents/autoresearch-*-subagent.md; fixes: none
- [x] **3.2** Citation-network rename (mechanical, one sweep): `autoresearch-core-skill/references/` → `autoresearch-skill/references/` across the 24 surviving skills + `test_autoresearch_protocol.bats` expected prefix + `test_default_behavior.bats` drift section; also `THIRD_PARTY_LICENSES.md` §1 vendored paths → router paths
    — **Why:** the protocol host's references moved; 24 skills + the enforcing test must follow in one commit
    — **Done when:** repo-wide grep for `autoresearch-core-skill` finds zero hits outside PLANS/CHANGELOG; protocol test green
    — **Consumers affected:** all retrofitted skills, CI
    — **Done:** citation rename swept 39 files (24 skills + tests + THIRD_PARTY + templates + scripts), 3 path forms (references/, SKILL.md, scripts/); protocol test green; default_behavior green; files: skills/*, tests/*, THIRD_PARTY_LICENSES.md; fixes: sweep caught /SKILL.md and /scripts/ forms beyond the planned references/ form
- [x] **3.3** HANDOFF2 retirement + renumber in ONE commit: dependency-map requiresSkills ×3 edges removed; guard loses HANDOFF2_OWNERS/TARGETS; HANDOFF3→2, HANDOFF4→3, HANDOFF5→4 renumbered across `test_skill_isolation.bats` (vars + argv arity), `test_requires_skills.bats` (extraction + both heredocs + argv offsets + per-family greps: cr_inline HANDOFF3→2, req_inline HANDOFF5→4); `requires_skills_autoresearch_loop_pulls_core` test retired (edge gone; map-entry equality test covers); AGENTS.md:22 declared-exceptions prose updated (exception retired; stale "HANDOFF3 multi-owner" mention corrected to the post-renumber reality)
    — **Why:** positional contract — partial renumber leaves silent argv mismatches (documented 3-cycle failure in #680)
    — **Done when:** `grep -rn "HANDOFF" tests/ AGENTS.md` shows a coherent 1–4 sequence; bats skill_isolation + requires_skills + cr_inline + req_inline green
    — **Consumers affected:** CI, installer edge derivation
    — **Done:** dependency-map ×3 edges removed; guard var block now exactly HANDOFF1–4 uniform pairs; renumber across isolation (vars+arity+allowed dict), requires_skills (extraction+heredoc+argv offsets+map-entry), cr_inline HANDOFF3→2, req_inline HANDOFF5→4; autoresearch loop test retired; AGENTS.md:22 prose updated (exception retired + stale HANDOFF3 multi-owner mention fixed); files: tests/*, installer/dependency-map.json, AGENTS.md; fixes: 3.2's blanket sed had renamed autoresearch-core-skill INSIDE the guard var block, silently defeating 3.3's exact-match deletion (generic-rewrites-before-anchors, cross-step form) — caught by map-entry assertion showing stacked HANDOFF2_TARGETS, repaired
- [x] **3.4** Installer + docs surfaces: pack-research preset 4→1 (position-preserving); README Autoresearch row (4→1) + 6 count literals 96→93 (lean unchanged — family not in lean); registry regenerated
    — **Why:** roster-affecting commit rule
    — **Done when:** zero old IDs in preset/README; counts equal disk; registry has router, zero removed IDs
    — **Consumers affected:** installer users, count-drift tests
    — **Done:** pack-research 11→8 skills (router position-preserving); README Autoresearch row (4→1) + 6 count literals 96→93 (lean unchanged); registry regenerated; files: installer/presets/pack-research.json, README.md, installer/registry.json; fixes: none

### Phase 4: Delete, final regen, recount

- [x] **4.1** Remove the 4 old dirs (pycache purge first)
    — **Why:** hard removal per AC; strictly after Phase 3
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry (4.2), counts (4.3)
    — **Done:** 4 dirs removed (3 empty shells rmdir'd; core's SKILL.md git rm'd); disk 93; files: skills/{4 dirs}; fixes: none
- [x] **4.2** Final `node installer/build-registry.mjs`; commit regenerated registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** registry has router, zero removed IDs; diff reviewed
    — **Consumers affected:** installer/init.mjs, npx installer
    — **Done:** final regen — router + 3 routes present, zero removed IDs, subagent requiresSkills updated; files: installer/registry.json; fixes: none
- [x] **4.3** Final sweep: counts equal disk (93); case-insensitive orphan grep for the 4 removed IDs (PLANS/CHANGELOG excepted)
    — **Why:** documented failure modes
    — **Done when:** greps clean; counts match disk
    — **Consumers affected:** deploy users, docs readers
    — **Done:** counts equal disk (93); orphan grep: only THIRD_PARTY karpathy template paths remained after first sweep — repointed to templates/ml|code|research/ (now 0); files: THIRD_PARTY_LICENSES.md; fixes: THIRD_PARTY §2 repoint

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [x] **5.1** Full bats suite green on the final tree
    — **Why:** isolation + governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
    — **Done:** full bats green on 559efc70 (0 not-ok; TS green); files: tests/; fixes: see LOG history
- [x] **5.2** Generalizer verification: ≤10240 bytes, ≤50-word description, rows resolve, route cross-refs resolve, no preload, no old-ID path strings
    — **Why:** router-pattern correctness conditions
    — **Done when:** all checks pass with measurements
    — **Consumers affected:** skill consumers
    — **Done:** router 5060 bytes ≤10240; description 34 words ≤50; 3 rows resolve; route cross-refs resolve; only preload hits are negations; zero old-ID path strings; files: skills/autoresearch-skill/; fixes: none
- [x] **5.3** Deliverables in trace: weight line, change list, residual list
    — **Why:** ticket AC
    — **Done when:** three blocks present
    — **Consumers affected:** reviewers, ticket close
    — **Done:** deliverables above (weight line, 5-part change list, 3-item residual list); files: PLANS/PLAN-688.md; fixes: none
- [x] **5.4** Full exit gate + `tier=full` memo for the final implementation SHA in Trace
    — **Why:** PR citation
    — **Done when:** memo matches final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)
    — **Done:** exit gate full on 559efc70, memo below; files: none; fixes: none

## Technical Notes

- The citation rename is the OPPOSITE risk of prior waves: instead of few consumers, one ubiquitous mechanical rename — `sed` across the retrofit network + one test prefix, all in one commit (3.2), gated by the protocol test that already enforces the exact strings.
- The loops' `metadata.protocol: autoresearch-default-on` moves to the router frontmatter (retrofitted skills keep their own — unchanged).
- TSV filenames in prose (`autoresearch-code-results.tsv` etc.) are runtime artifact names, not paths — keep.
- Loop templates are the loops' working artifacts (`program.md`, `train.py.template`) — absorbed under `templates/<loop>/`, paths updated in route prose only.

## Dependencies

- #687 merged (satisfied — 899ec27).

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| 24-file citation rename misses a file/form | repo-wide grep gate in 3.2 + protocol test enforces exact strings |
| HANDOFF renumber argv drift | single-commit renumber + 4-file grep + dedicated bats run (3.3 Done-when) |
| Core-spine rewrite loses protocol details | spine carries core's sections verbatim-structured; references/ absorbed unchanged at root |
| Registry/count drift | roster-change rule; count-drift tests |

## Trace

LOG phase-1: docs-only; clean baseline captured pre-edit (bats 0, ts 0).
GATE (phase-1 tree) tier=light lint=n.a typecheck=n.a build=- unit=n.a e2e=n.a
LOG phase-2/4: single roster-final commit cycle (moves emptied the old dirs at once). Gate history: clean baseline (0 red); first gate red ×6 — map-entry expected-delta (root cause: 3.2's blanket sed renamed autoresearch-core-skill INSIDE the guard var block before 3.3's exact-match deletion, silently defeating it; stacked HANDOFF2_TARGETS), yaml_validates ×3 (removed dirs), subagent allow assertions ×3 (loop skill → router). All fixed in-cycle; guard-family + autoresearch tests green; final full gate green.


(appended at execution: phase commits, gate memos, deliverables)

LOG phase-5: exit gate full on 559efc70 — bats 0 failures, TS green, registry regen content-stable.

## Deliverables (generalizer output contract)

**Weight line**: trigger-time SKILL.md load: 4 catalog entries, 21,829 bytes / ~5.5k tokens (avg ~5.5KB per trigger) + core references always one hop away → 1 router at 5,060 bytes (~1.3k tokens, incl. the full protocol spine) + one route file on match; catalog rows 96 → 93; lean unchanged (family not in lean); subagent allows 2 → 1 ×3; installer requiresSkills edges 7 → 4; description: per-skill 15–35 words × 4 → one 34-word description.

**Change list**:
- Generalized: core's methodology (5-stage loop, evaluator contract, stuck detection, injection boundary, autonomy, crash recovery) → router spine, stated once; citation convention (skill-root-relative) stated once.
- Conditionalized: 3 loops behind WHEN+WHAT load rules with their overrides + per-loop templates; references/*.md on demand.
- Modularized: core references/ + scripts/ at router root serving the catalog-wide retrofit network; templates/<loop>/ per loop.
- Deleted: 4 skill identities; HANDOFF2 multi-owner pair (retired by construction — 7→4 installer edges); core's obsolete "When to use me" self-description; loop "Load me" phrasing.
- Rewired (rename, not rewire): 24-skill citation network `autoresearch-core-skill/…` → `autoresearch-skill/…` — the protocol-host pattern makes consolidation a namespace change.

**Residual list (owner)**:
- The retrofit citation format (`autoresearch-skill/references/*.md`) is now load-bearing across 24 skills — future moves of those references must repeat the sweep (protocol test enforces).
- Loop TSV filenames (`autoresearch-code-results.tsv` etc.) are runtime artifact names — unchanged by design.
- AGENTS.md HANDOFF prose now describes 4 uniform pairs; a future multi-owner pair reintroduces the OWNERS/TARGETS shape — the guard python would need the loop form again.

## Trace
GATE 559efc70 tier=full lint=t typecheck=n.a build=t unit=t e2e=n.a
