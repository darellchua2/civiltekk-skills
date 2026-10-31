# PLAN: Consolidate 2 install-assistant skills into install-assistant-skill

**Branch**: feat/691
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/691
**Base**: main

## Acceptance Criteria

- [ ] Router ships: ≤10240 bytes, ≤50-word description, triggers preserved (install mcp, enable pack, find a skill, install skill, update, dry-run), decision tree, consent spine, load table (2 routes), gates, zero-preload
- [ ] 2 route files with headers (`mcp`, `catalog`); civiltekk-install-assistant's 3 values files → `references/routes/catalog/` detail dir; inventory script absorbed; no old-ID path strings
- [ ] Consumers rewired: deploy/.AGENTS.md prose, shipped config (2→1), lean (1→1 swap), README (quick-route line, prose, Configuration row 2→1, counts 85→84), cad-specialist convention mention; registry regenerated
- [ ] 2 old dirs hard-removed; orphan-reference grep clean (PLANS/CHANGELOG/LEARNINGS-history excepted)
- [ ] Full bats green (Configuration-category test verified dynamic); generalizer output contract in trace

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/install-assistant-skill/` (new) | Phase 1 | installer users, registry, cad-specialist prose, deploy/.AGENTS.md | med |
| `deploy/opencode.json` allow (mcp) + `deploy/skill-profiles.json` lean (mcp) | router named | skill_profiles tests, README primary-visible | low |
| `deploy/.AGENTS.md` §Skill & Agent Installation prose | router named | user-level deploy docs (deployed copy) | low |
| `README.md` (quick-route line, mcp prose, Configuration row, counts) | final roster | count-drift tests | low |
| `skills/cad-specialist-skill/SKILL.md:62` convention mention | router named | cad router readers | low |
| Configuration-category count test (dynamic) | final roster | CI — verify it reads both sides | low |
| 2 old dirs (delete) | rewires landed | registry, counts | high |

## Implementation Phases

### Phase 1: Audit + build (single small family — combined)

- [ ] **1.1** Record dispositions: spine = shared consent/dry-run invariants + capability bindings + combined route detection; routes `mcp` (4-step method + precheck table + house rules) and `catalog` (route detection + values files as detail dir); both frontmatters carry `harness: "opencode"` → router; LEARNINGS citation = dated history (justified residual)
    — **Why:** both skills are already router-shaped; the merge is mostly mechanical
    — **Done when:** Audit Notes recorded in this PLAN
    — **Consumers affected:** Phase 2
- [ ] **1.2** Moves + transform: mcp SKILL.md → `references/routes/mcp.md` (header; `<this-skill-dir>/scripts/` → `scripts/`), inventory.mjs → `scripts/`; civiltekk-install-assistant SKILL.md → `references/routes/catalog.md` (header; its route-detection table folded into catalog route), 3 values files → `references/routes/catalog/{find,install,maintain}.md`; residual grep
    — **Why:** values files keep their load rules under the catalog route
    — **Done when:** 2 route files + catalog detail dir; residual clean
    — **Consumers affected:** router load table
- [ ] **1.3** Router SKILL.md: frontmatter (name = dir, harness opencode, category Configuration, ≤50 words), combined decision tree, consent spine, 2-row load table, gates
    — **Why:** the contract
    — **Done when:** ≤10240 bytes; ≤50 words; 2 rows
    — **Consumers affected:** installer users

### Phase 2: Rewire + delete + verify

- [ ] **2.1** Consumers: deploy/.AGENTS.md prose; shipped config 2→1; lean mcp→router (stays 59); cad-specialist:62 mention; README quick-route line + prose + Configuration row 2→1 + counts 85→84; registry regenerated
    — **Why:** roster-affecting rule
    — **Done when:** zero old IDs outside LEARNINGS history; counts equal disk
    — **Consumers affected:** installer users, count-drift tests
- [ ] **2.2** Remove the 2 old dirs; final regen; orphan sweep
    — **Why:** hard removal per AC
    — **Done when:** dirs gone; greps clean
    — **Consumers affected:** registry
- [ ] **2.3** Full bats green (Configuration-category test verified reading both sides); generalizer verification (bytes/words/rows/residual); deliverables (weight line, change list, residual list); `tier=full` exit-gate memo for the final SHA
    — **Why:** ticket AC + PR citation
    — **Done when:** 0 failures; memo matches final pushed SHA
    — **Consumers affected:** governance, CI, PR step

## Technical Notes

- The two skills' consent contracts are the same invariant stated twice — the spine states it once ("dry-run → show resolved set → consent → verify → never auto-install").
- mcp route's step-2 precheck table and step-3 global-scope guard (configurator-repo-only) are protocol contracts — keep verbatim.

## Dependencies

- #690 merged (satisfied — e35972f).

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Configuration-category test semantics | verify dynamic read at the gate (2.3) |
| deploy/.AGENTS.md is ALSO a deployed file — repo edit must not desync the deployed copy rationale | prose-only name repoint; deploy step copies it verbatim |

## Trace

(appended at execution: phase commits, gate memos, deliverables)
