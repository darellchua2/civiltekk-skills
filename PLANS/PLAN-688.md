# PLAN: Consolidate 4 autoresearch skills into autoresearch-skill router

**Branch**: feat/688
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/688
**Base**: main

## Acceptance Criteria

- [ ] Router ships: ≤10240 bytes, ≤50-word description, triggers preserved (autonomous loop, code optimization, ML training, literature review, keep/revert), decision tree, core protocol as spine, load table (3 routes), gates, zero-preload
- [ ] 3 route files with headers; core `references/` at router root; scripts + per-loop templates absorbed; no old-ID path strings in scripts/templates/fenced blocks
- [ ] HANDOFF2 (multi-owner autoresearch pair) retired: dependency-map ×3 edges removed + guard renumbered across ALL affected test files in one commit; `grep -rn "HANDOFF" tests/` re-verified post-renumber
- [ ] Retrofit citation network repointed: all surviving skills citing `autoresearch-core-skill/references/` (24 files) renamed to `autoresearch-skill/references/`; protocol test expected prefix updated
- [ ] 3 loop subagents rewired (router allow); pack-research preset 4→1; README row + count literals (96→93); AGENTS.md prose (exception retired + stale HANDOFF3 mention fixed); THIRD_PARTY §1 paths repointed; old dirs hard-removed; orphan grep clean
- [ ] Registry regen + count literals ride roster-affecting commits; full bats green; generalizer output contract (weight line, change list, residual list) in trace

## Audit Baseline (measured at plan time)

4 skills, 21,829 bytes of SKILL.md + 15,132 bytes core `references/*.md` (5 files) + 15,230 bytes core scripts (3) + per-loop `templates/` dirs. Not in lean, not in shipped-config allows. HANDOFF2 = the multi-owner pair (3 owners → core). The core skill is the #602 **shared protocol host**: 24 surviving skills + 5 templates/scripts cite `autoresearch-core-skill/references/*.md` by path (prose citations, NOT installer edges), mechanically enforced by `tests/test_autoresearch_protocol.bats` (`tier1_*_cites_all_5_references` greps the exact prefix per retrofitted skill).

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

- [ ] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 4 SKILL.mds; inventory ALL path citations (`autoresearch-core-skill/references|scripts|templates`) across the 4 members + the 24-skill retrofit network + templates + scripts, with their post-merge forms
    — **Why:** the citation network is this ticket's dominant consumer surface; every path form must be inventoried before the transform
    — **Done when:** zero un-dispositioned entities; citation inventory complete with counts per file
    — **Consumers affected:** Phase 2 transform, Phase 3 rewire
- [ ] **1.2** Confirm boundary (all 4 merge; core becomes spine + shared references) and router layout (references at root, scripts at root, templates per-loop subdir); record the citation-format decision (skill-root-relative) in the layout
    — **Why:** the citation format must be decided once — 24 files depend on it
    — **Done when:** layout + citation format recorded in Audit Notes
    — **Consumers affected:** Phases 2–3

### Phase 2: Build skills/autoresearch-skill/

- [ ] **2.1** Write the router SKILL.md: frontmatter (name `autoresearch-skill`, Apache-2.0, `metadata.protocol: autoresearch-default-on`, category Autoresearch, ≤50-word description with family triggers), identity (mechanical evaluator, no self-judgment), the 5-stage loop + evaluator contract + stuck detection + injection boundary + autonomy directive as the spine (from core), load table (3 routes), references/scripts index, hard rules, gates
    — **Why:** core IS the shared protocol — it becomes the router spine, not a route
    — **Done when:** file exists; ≤10240 bytes; ≤50 words; 3 rows; no preload
    — **Consumers affected:** subagents (3.1), registry, retrofit citations (3.2)
- [ ] **2.2** Moves + transform: `git mv` loop SKILL.mds → `references/routes/{code,ml,research}.md`; core `references/*.md` → router root `references/`; core `scripts/*` → `scripts/`; loop `templates/*` → `templates/<loop>/`; transform route files (headers with Load-when/Skip-when; citation rewrites: `autoresearch-core-skill/references/` → `references/`, `autoresearch-<loop>-skill/templates/` → `templates/<loop>/`; triggers cross-refs → route names; core's obsolete "When to use me" folded into spine). Anchor-specific rewrites before generic sweeps; residual grep for any `autoresearch-` path form
    — **Why:** the moves create the layout the 24-file citation rename targets; mangled anchors are the documented failure mode
    — **Done when:** 3 route files with headers; all absorbed files present; residual old-ID path grep clean
    — **Consumers affected:** 3.2 citation rename target paths
- [ ] **2.3** Preserve provenance: per-route attribution blocks kept (uditgoenka/karpathy/wjgoarxiv MIT notices); scripts keep executable bits; AST/bash -n syntax checks over absorbed scripts
    — **Why:** vendored MIT attribution and working scripts must survive
    — **Done when:** attribution present per route; `bash -n` clean on .sh, `py_compile` clean on .py
    — **Consumers affected:** compliance readers, script runtime

### Phase 3: Rewire consumers (before any deletion)

- [ ] **3.1** 3 loop subagents: allow 2→1 (`autoresearch-skill`); prose references → route names; verify effect-line intact (Wave-2 bug class)
    — **Why:** agents must not reference removed skills; YAML assertions in test_autoresearch_skills must stay green
    — **Done when:** grep of the 3 agents finds zero old IDs; YAML allow assertion passes
    — **Consumers affected:** registry build, runtime
- [ ] **3.2** Citation-network rename (mechanical, one sweep): `autoresearch-core-skill/references/` → `autoresearch-skill/references/` across the 24 surviving skills + `test_autoresearch_protocol.bats` expected prefix + `test_default_behavior.bats` drift section; also `THIRD_PARTY_LICENSES.md` §1 vendored paths → router paths
    — **Why:** the protocol host's references moved; 24 skills + the enforcing test must follow in one commit
    — **Done when:** repo-wide grep for `autoresearch-core-skill` finds zero hits outside PLANS/CHANGELOG; protocol test green
    — **Consumers affected:** all retrofitted skills, CI
- [ ] **3.3** HANDOFF2 retirement + renumber in ONE commit: dependency-map requiresSkills ×3 edges removed; guard loses HANDOFF2_OWNERS/TARGETS; HANDOFF3→2, HANDOFF4→3, HANDOFF5→4 renumbered across `test_skill_isolation.bats` (vars + argv arity), `test_requires_skills.bats` (extraction + both heredocs + argv offsets + per-family greps: cr_inline HANDOFF3→2, req_inline HANDOFF5→4); `requires_skills_autoresearch_loop_pulls_core` test retired (edge gone; map-entry equality test covers); AGENTS.md:22 declared-exceptions prose updated (exception retired; stale "HANDOFF3 multi-owner" mention corrected to the post-renumber reality)
    — **Why:** positional contract — partial renumber leaves silent argv mismatches (documented 3-cycle failure in #680)
    — **Done when:** `grep -rn "HANDOFF" tests/ AGENTS.md` shows a coherent 1–4 sequence; bats skill_isolation + requires_skills + cr_inline + req_inline green
    — **Consumers affected:** CI, installer edge derivation
- [ ] **3.4** Installer + docs surfaces: pack-research preset 4→1 (position-preserving); README Autoresearch row (4→1) + 6 count literals 96→93 (lean unchanged — family not in lean); registry regenerated
    — **Why:** roster-affecting commit rule
    — **Done when:** zero old IDs in preset/README; counts equal disk; registry has router, zero removed IDs
    — **Consumers affected:** installer users, count-drift tests

### Phase 4: Delete, final regen, recount

- [ ] **4.1** Remove the 4 old dirs (pycache purge first)
    — **Why:** hard removal per AC; strictly after Phase 3
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry (4.2), counts (4.3)
- [ ] **4.2** Final `node installer/build-registry.mjs`; commit regenerated registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** registry has router, zero removed IDs; diff reviewed
    — **Consumers affected:** installer/init.mjs, npx installer
- [ ] **4.3** Final sweep: counts equal disk (93); case-insensitive orphan grep for the 4 removed IDs (PLANS/CHANGELOG excepted)
    — **Why:** documented failure modes
    — **Done when:** greps clean; counts match disk
    — **Consumers affected:** deploy users, docs readers

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [ ] **5.1** Full bats suite green on the final tree
    — **Why:** isolation + governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
- [ ] **5.2** Generalizer verification: ≤10240 bytes, ≤50-word description, rows resolve, route cross-refs resolve, no preload, no old-ID path strings
    — **Why:** router-pattern correctness conditions
    — **Done when:** all checks pass with measurements
    — **Consumers affected:** skill consumers
- [ ] **5.3** Deliverables in trace: weight line, change list, residual list
    — **Why:** ticket AC
    — **Done when:** three blocks present
    — **Consumers affected:** reviewers, ticket close
- [ ] **5.4** Full exit gate + `tier=full` memo for the final implementation SHA in Trace
    — **Why:** PR citation
    — **Done when:** memo matches final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)

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

(appended at execution: phase commits, gate memos, deliverables)
