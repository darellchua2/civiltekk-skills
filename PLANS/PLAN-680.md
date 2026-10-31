# PLAN: Consolidate office-document skills into one router skill

**Branch**: feat/680
**Issue**: https://github.com/darellchua2/civiltekk-skills/issues/680
**Base**: main

## Acceptance Criteria

- [ ] Generalizer detector pass (1–8) documented; merge/sibling boundary recorded
- [ ] Router skill ships: SKILL.md ≤10KB (~2.5k tokens), decision tree, spine, load table, gates in router; description ≤50 words, triggers preserved
- [ ] pptx vendored `scripts/_common` constraint resolved (single tree; guard updated or retired)
- [ ] markitdown/docling routes follow civiltekk-install-assistant conventions (dry-run + consent, never auto-install)
- [ ] Replaced skills hard-removed; orphan-reference grep clean (historical PLANS excepted)
- [ ] Consumers rewired: subagent permission allowlists, presets, `README.md`, `deploy/setup.sh` + `setup.ps1`, registry regenerated
- [ ] Full bats suite passes
- [ ] Generalizer output contract deliverables: weight line, change list, residual list

## Dependency & Consumer Map

| Node (file/module) | Depends on (must precede) | Consumers (who depends on this) | Change risk |
|---------------------|---------------------------|---------------------------------|-------------|
| `skills/office-document-router-skill/` (new) | Phase 1 audit | 9 subagents' allowlists, presets, registry, npx users | med |
| 9 subagent frontmatters (office-document-router, docx-creation, xlsx-specialist, pptx-specialist, documentation, discovery, requirements-specialist, startup-founder, technical-design-specialist) | router exists | OpenCode runtime, registry build, requiresSkills derivation | med |
| `deploy/skill-profiles.json` lean array (docling, markitdown, pdf entries) | router named + old IDs final | README primary-visible count literal; count-drift tests | med |
| `installer/dependency-map.json` (impliesMcp markitdown/docling; requiresSkills HANDOFF1 pptx pair) | removal set final | installer/init.mjs | med |
| `tests/test_skill_isolation.bats` rule 4 (pptx _common byte-identity) + HANDOFF1 blocks (`test_requires_skills.bats`, isolation HANDOFF vars) | single _common tree landed; HANDOFF1 pair retired | repo governance, CI | med |
| 11 old skill dirs (delete) | ALL consumer rewires landed (Phase 3) | registry build, counts, README, AGENTS.md routing section | high |
| `AGENTS.md` Office Document Extraction Routing section | router exists | docs readers | low |
| `installer/registry.json` | all frontmatter final; producer `installer/build-registry.mjs` run per roster change (not edited by hand) | installer/init.mjs, npx installer | med |
| `README.md`, `deploy/setup.sh`, `deploy/setup.ps1` | final roster post-deletion | deploy users, docs readers | low |

Phase ordering constraint: no deletion (4.1) before every consumer is rewired (Phase 3); registry regeneration rides every roster-affecting commit (project anti-pattern: skill-moves-are-roster-changes).

## Implementation Phases

### Phase 1: Generalizer audit (detector pass + boundary)

- [ ] **1.1** Run named-entity, anecdote→rule, constants, and contradiction detectors over the 11 SKILL.mds; record every proper noun / anecdote / magic number with its disposition in a new `## Audit Notes` section of this PLAN
    — **Why:** the detector pass drives route-file content and catches cross-skill references before the merge
    — **Done when:** zero un-dispositioned named entities remain; notes list findings + dispositions
    — **Consumers affected:** Phase 2 route files
- [ ] **1.2** Confirm the merge/sibling boundary per the sizing rule; decide `interactive-document-rendering-skill` (in-family or out) and whether the pptx trio merges with a single `_common` tree; map every consumer hit from the repo-wide ID grep into the Phase 3 rewire list
    — **Why:** the Phase 4 deletion list and Phase 3 rewire list must be exact before building
    — **Done when:** audit notes name the final merge set with the rule outcome each, plus the complete consumer list (subagents, presets, profiles, guards, AGENTS.md, README)
    — **Consumers affected:** Phases 2–4

### Phase 2: Build skills/office-document-router-skill/

- [ ] **2.1** Write `skills/office-document-router-skill/SKILL.md` router: frontmatter (name matching dir, description ≤50 words carrying the family triggers — DOCX, XLSX, PPTX, PDF, OOXML, document extraction, thumbnails, markitdown, docling —, license, compatibility, metadata, category), identity, decision tree (document task → route), shared document spine, load table, hard rules, gates
    — **Why:** the router is the contract every consumer and route file hangs off
    — **Done when:** file exists; `wc -c` ≤ 10240; description ≤50 words; all 11 routes represented; no preload instructions
    — **Consumers affected:** subagents (Phase 3), registry (4.2), end users
- [ ] **2.2** Create `references/routes/<id>.md` for each merged route via `git mv` of each SKILL.md + transform (strip frontmatter → WHEN+WHAT header, self-references → `<id>/` paths, cross-skill references → route/sibling wording); absorb reference dirs and scripts trees beside their route files; pptx trio's `scripts/_common` unified to ONE tree at the skill root `scripts/_common`
    — **Why:** route files carry merged mechanics behind load rules; the single `_common` retires the drift guard by construction
    — **Done when:** 11 route files with headers; every `<id>/…` target exists; zero old-ID path strings in .py or fenced blocks; `_common` exists exactly once
    — **Consumers affected:** router load table (2.1)
- [ ] **2.3** Preserve provenance: LICENSE files carried to the skill root or route dirs; merged `requirements.txt` when present (dependency-conflict audit); AST syntax check over absorbed scripts
    — **Why:** licenses and working scripts must survive the merge unmodified
    — **Done when:** every old LICENSE text present verbatim; scripts parse clean (`ast.parse`); no conflicting pins
    — **Consumers affected:** compliance readers, script runtime

### Phase 3: Rewire consumers (before any deletion)

- [ ] **3.1** Rewire the 9 subagent frontmatters: office-skill allow rules → single `office-document-router-skill` allow; routing tables point at router routes; prose references → route names
    — **Why:** agents must not allow or reference skills Phase 4 removes; allow rules feed requiresSkills derivation
    — **Done when:** grep of agents/ finds zero references to removed IDs outside install-if-missing/MCP-context mentions
    — **Consumers affected:** OpenCode runtime, registry (4.2)
- [ ] **3.2** Update `deploy/skill-profiles.json` lean array (docling/markitdown/pdf entries → `office-document-router-skill`), `installer/presets/pack-business.json` + `pack-docs.json` rosters, and `installer/dependency-map.json` (remove impliesMcp markitdown/docling entries — on-demand MCP enablement moves into the routes per install-assistant conventions; remove the HANDOFF1 requiresSkills pptx pair)
    — **Why:** installer surfaces must match the post-merge installable set or presets/edges dangle
    — **Done when:** JSON parses; zero removed IDs in the three files; dependency-map comment updated
    — **Consumers affected:** installer users, init.mjs
- [ ] **3.3** Update the guard tests: retire the pptx `_common` byte-identity rule (test_skill_isolation.bats rule 4 block) and the HANDOFF1 pair (isolation test vars + test_requires_skills.bats HANDOFF1 assertions) — retired BY CONSTRUCTION (single tree, no handoff left)
    — **Why:** guards enforcing the pre-merge topology would fail on the correct post-merge tree
    — **Done when:** bats skill_isolation + requires_skills tests pass on the merged tree
    — **Consumers affected:** repo governance, CI
- [ ] **3.4** Repoint `AGENTS.md` Office Document Extraction Routing section at the router routes; update README count literals (incl. primary-visible) IN THE SAME COMMITS as roster changes per project anti-pattern; regenerate `installer/registry.json`
    — **Why:** docs routing and generated artifacts must track the tree
    — **Done when:** AGENTS.md section references router routes; count literals equal disk; registry contains the router, zero removed IDs
    — **Consumers affected:** docs readers, installer

### Phase 4: Delete, final regen, recount

- [ ] **4.1** `git rm -r` the 11 replaced skill dirs
    — **Why:** hard removal per AC; strictly after Phase 3
    — **Done when:** dirs gone; only intended deletions staged
    — **Consumers affected:** registry (4.2), counts (4.3)
- [ ] **4.2** Final `node installer/build-registry.mjs`; commit regenerated registry
    — **Why:** generated artifact tracks the tree
    — **Done when:** registry has the router + zero removed IDs; diff reviewed
    — **Consumers affected:** installer/init.mjs, npx installer
- [ ] **4.3** Final count sweep: README + deploy scripts counts equal `ls skills/ | wc -l`; case-insensitive orphan grep for the 11 removed IDs (historical PLANS excepted)
    — **Why:** count drift and dangling references are the documented failure modes
    — **Done when:** greps clean; counts match disk
    — **Consumers affected:** deploy users, docs readers

### Phase 5: Verify + deliverables (ticket exit gate — full)

- [ ] **5.1** Full bats suite green on the final tree
    — **Why:** isolation + governance enforcement
    — **Done when:** exit 0, zero `not ok`
    — **Consumers affected:** repo governance, CI
- [ ] **5.2** Generalizer verification on the router: ≤10240 bytes, ≤50-word description, load-table rows resolve, route cross-refs resolve, no preload rules, no old-ID path strings
    — **Why:** router-pattern correctness conditions
    — **Done when:** all checks pass with recorded measurements
    — **Consumers affected:** skill consumers
- [ ] **5.3** Record deliverables in the PLAN trace: weight line before→after, change list, residual list
    — **Why:** ticket AC requires reviewable contract deliverables
    — **Done when:** three deliverable blocks present with final numbers
    — **Consumers affected:** reviewers, ticket close
- [ ] **5.4** Run the full exit gate and write the `tier=full` memo for the final implementation SHA into the PLAN `## Trace`
    — **Why:** PR step cites the memo for the pushed SHA
    — **Done when:** memo line present matching the final pushed SHA
    — **Consumers affected:** PR creation (Step 10a)

## Technical Notes

- markitdown/docling become ROUTES whose install-if-absent instruction is the MCP pack (`--enable-pack markitdown` / docling via mcp-install-assistant, consent-gated) — the impliesMcp auto-enable edges are removed so installing the router does not silently enable MCP servers (on-demand parity with Wave 1's sibling contract).
- The pptx trio merges with one `scripts/_common` tree at the router root; per-format scripts stay in per-route subdirs; the byte-identity guard retires by construction.
- deploy/opencode.json MCP server definitions (markitdown, docling) are infrastructure — unchanged; only the skill→MCP edges move.
- Router routes load one-at-a-time; extraction-tier guidance (markitdown → docling escalation) lives in the router spine, replacing the AGENTS.md informal table.

## Dependencies

- Wave 1 (#679) merged (satisfied — main carries cad-specialist-skill).

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| 9 subagent rewrites drift | scripted exact-anchor swaps + grep gates per step |
| lean-array length change breaks README primary-visible literal | 3.4 updates both in the same commit; count-drift tests verify |
| guard retirement leaves stale HANDOFF vars referenced elsewhere | 3.3 greps tests/ for HANDOFF1 before finishing |
| pptx scripts assume old relative layout | 2.2 rewrite + AST check + 5.2 sweep |
| registry/README counts drift mid-phase | regen + literals ride every roster-affecting commit (Wave 1 lesson) |

## Trace

(appended at execution: phase commits, gate memos, deliverables)
